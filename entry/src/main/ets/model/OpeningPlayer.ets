import { common } from '@kit.AbilityKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';

export type OpeningState = 'idle' | 'loading' | 'playing' | 'paused' | 'ended' | 'error';
export type OpeningAudioLoader = (index: number) => Promise<string>;
export type OpeningObserver = (state: OpeningState, index: number, error: string) => void;

// Each sentence is an independent audio clip. Highlight follows actual AVPlayer state.
export class OpeningPlayer {
  private player: media.AVPlayer | null = null;
  private file: fileIo.File | null = null;
  private generation: number = 0;
  private paused: boolean = false;
  private running: boolean = false;
  private index: number = 0;
  private count: number = 0;
  private paths: string[] = [];
  private rate: number = 1;
  private loader: OpeningAudioLoader | null = null;
  private observer: OpeningObserver | null = null;
  private completed: ((value: boolean) => void) | null = null;
  private timer: number = -1;

  private emit(state: OpeningState, error: string = ''): void { this.observer?.(state, this.index, error); }
  private speed(): media.PlaybackSpeed {
    if (this.rate === 0.75) return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    if (this.rate === 1.25) return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    if (this.rate === 1.5) return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }
  async start(count: number, loader: OpeningAudioLoader, rate: number, observer: OpeningObserver): Promise<void> {
    await this.stop();
    this.count = count; this.loader = loader; this.rate = rate; this.observer = observer;
    this.index = 0; this.paths = []; this.paused = false;
    this.run();
  }
  private async release(): Promise<void> {
    clearTimeout(this.timer);
    const player = this.player; this.player = null;
    if (player) { try { await player.release(); } catch (e) {} }
    const file = this.file; this.file = null;
    if (file) { try { fileIo.closeSync(file); } catch (e) {} }
  }
  private async clip(path: string, generation: number): Promise<boolean> {
    const player = await media.createAVPlayer();
    if (generation !== this.generation) { await player.release(); return false; }
    this.player = player;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY); this.file = file;
    const done = new Promise<boolean>((resolve) => { this.completed = resolve; });
    const finish = (ok: boolean): void => { if (generation !== this.generation) return; const resolve = this.completed; this.completed = null; clearTimeout(this.timer); resolve?.(ok); };
    player.on('error', () => { if (generation === this.generation) finish(false); });
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (generation !== this.generation) return;
      if (state === 'initialized') player.prepare().catch(() => finish(false));
      else if (state === 'prepared') {
        clearTimeout(this.timer);
        try {
          player.setSpeed(this.speed());
          if (this.paused) this.emit('paused');
          else player.play().catch(() => finish(false));
        } catch (e) { finish(false); }
      } else if (state === 'playing') this.emit('playing');
      else if (state === 'paused') this.emit('paused');
      else if (state === 'completed') finish(true);
    });
    this.timer = setTimeout(() => finish(false), 15000);
    player.fdSrc = { fd: file.fd, offset: 0, length: fileIo.statSync(path).size };
    const success = await done;
    if (generation === this.generation) await this.release();
    return success;
  }
  private async run(): Promise<void> {
    if (this.running || !this.loader) return;
    this.running = true;
    const generation = this.generation;
    try {
      while (this.index < this.count && generation === this.generation) {
        if (this.paused) { this.emit('paused'); return; }
        this.emit('loading');
        const index = this.index;
        const path = this.paths[index] || await this.loader(index);
        if (generation !== this.generation) return;
        this.paths[index] = path;
        if (this.paused) { this.emit('paused'); return; }
        if (!await this.clip(path, generation)) {
          if (generation === this.generation) this.emit('error', '开场音频未能播放，可重试或直接开始答题。');
          return;
        }
        if (generation !== this.generation) return;
        this.index++;
      }
      if (generation === this.generation) this.emit('ended');
    } catch (e) {
      if (generation === this.generation) { await this.release(); this.emit('error', '开场合成或播放失败，可重试或直接开始答题。'); }
    } finally { if (generation === this.generation) this.running = false; }
  }
  async pause(): Promise<void> {
    this.paused = true;
    if (this.player?.state === 'playing') await this.player.pause();
    this.emit('paused');
  }
  async resume(): Promise<void> {
    this.paused = false;
    if (this.player && ['paused', 'prepared'].includes(this.player.state)) await this.player.play();
    else this.run();
  }
  async stop(): Promise<void> {
    this.generation++; this.paused = false; this.running = false;
    const finish = this.completed; this.completed = null; finish?.(false);
    this.observer = null; this.loader = null;
    await this.release();
  }
}

