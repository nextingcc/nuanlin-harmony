import { webSocket } from '@kit.NetworkKit';
import { audio } from '@kit.AudioKit';
import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Api, VoiceSession } from './Api';

export class VoiceRecorder {
  private ws: webSocket.WebSocket | null = null;
  private capturer: audio.AudioCapturer | null = null;
  private busy: boolean = false;
  private recording: boolean = false;
  private generation: number = 0;
  private bytesSent: number = 0;
  private timeout: number = -1;
  private settleStart: ((ok: boolean) => void) | null = null;
  private onPreview: (text: string) => void = () => {};
  private onFinal: (text: string) => void = () => {};
  private onError: (message: string) => void = () => {};
  private onLevel: (level: number) => void = () => {};

  isRecording(): boolean { return this.recording; }
  isBusy(): boolean { return this.busy; }

  async start(interviewId: string, questionId: string, revision: number,
    onPreview: (text: string) => void, onFinal: (text: string) => void,
    onError: (message: string) => void): Promise<boolean> {
    return this.connect(() => Api.voiceSession(interviewId, questionId, revision), onPreview, onFinal, onError);
  }

  async startDictation(onPreview: (text: string) => void, onFinal: (text: string) => void,
    onError: (message: string) => void, onLevel: (level: number) => void): Promise<boolean> {
    return this.connect(() => Api.dictationSession(), onPreview, onFinal, onError, onLevel);
  }

  private async connect(createSession: () => Promise<VoiceSession>,
    onPreview: (text: string) => void, onFinal: (text: string) => void,
    onError: (message: string) => void, onLevel: (level: number) => void = () => {}): Promise<boolean> {
    if (this.busy) return false;
    this.busy = true;
    this.bytesSent = 0;
    const generation = ++this.generation;
    this.onPreview = onPreview;
    this.onFinal = onFinal;
    this.onError = onError;
    this.onLevel = onLevel;
    try {
      const task = await createSession();
      if (generation !== this.generation) return false;
      const ws = webSocket.createWebSocket();
      this.ws = ws;
      const ready = new Promise<boolean>((resolve) => { this.settleStart = resolve; });
      this.timeout = setTimeout(() => {
        this.fail(generation, '语音连接超时，可重试或使用文字回答。');
      }, 12000);
      ws.on('open', () => {
        if (generation === this.generation) ws.send(JSON.stringify({ ticket: task.ticket }));
      });
      ws.on('message', (error: BusinessError, value: string | ArrayBuffer) => {
        if (generation !== this.generation || typeof value !== 'string') return;
        try {
          const frame = JSON.parse(value) as Record<string, Object>;
          const type = frame['type'] as string;
          if (type === 'ready') {
            hilog.info(0, 'nuanlinVoice', 'ASR channel ready');
            this.startCapture(generation);
          } else if (type === 'preview') {
            const text = (frame['text'] as string) ?? '';
            const partial = (frame['partial'] as string) ?? '';
            this.onPreview(text + (partial.length > 0 && !text.endsWith(partial) ? partial : ''));
          } else if (type === 'final') {
            hilog.info(0, 'nuanlinVoice', 'ASR final received');
            const text = (frame['text'] as string) ?? '';
            this.cancel();
            onFinal(text);
          } else if (type === 'error') {
            this.fail(generation, (frame['message'] as string) ?? '语音识别失败，请重试或打字。');
          }
        } catch (e) { this.fail(generation, '语音结果无法读取，请重试或打字。'); }
      });
      ws.on('error', () => { this.fail(generation, '语音连接失败，可重试或使用文字回答。'); });
      ws.on('close', () => { this.fail(generation, '语音连接中断，已有文字仍保留。'); });
      // Reuse the backend path and cookie authentication; never put the cookie in the URL.
      ws.connect(Api.voiceStreamUrl(task.path), { header: { 'Cookie': Api.voiceCookie() } })
        .catch(() => { this.fail(generation, '语音连接失败，请检查服务连接。'); });
      return await ready;
    } catch (e) {
      this.fail(generation, (e as Error).message);
      return false;
    }
  }

  private async startCapture(generation: number): Promise<void> {
    if (this.capturer !== null || this.recording || generation !== this.generation) return;
    try {
      await this.playReadyTone();
      if (generation !== this.generation) return;
      const capturer = await audio.createAudioCapturer({
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: { source: audio.SourceType.SOURCE_TYPE_MIC, capturerFlags: 0 }
      });
      if (generation !== this.generation) { await capturer.release(); return; }
      this.capturer = capturer;
      capturer.on('readData', (buffer: ArrayBuffer) => {
        if (generation !== this.generation || !this.recording || this.ws === null) return;
        const samples = new DataView(buffer);
        let peak = 0;
        for (let offset = 0; offset + 1 < samples.byteLength; offset += 16) {
          peak = Math.max(peak, Math.abs(samples.getInt16(offset, true)));
        }
        this.onLevel(Math.min(1, peak / 10000));
        for (let offset = 0; offset < buffer.byteLength; offset += 1280) {
          const chunk = buffer.slice(offset, Math.min(offset + 1280, buffer.byteLength));
          if (chunk.byteLength % 2 !== 0) { this.fail(generation, '录音格式异常，请重试。'); return; }
          this.bytesSent += chunk.byteLength;
          this.ws.send(chunk).catch(() => { this.fail(generation, '音频发送失败，请重试或打字。'); });
        }
      });
      this.recording = true;
      await capturer.start();
      if (generation !== this.generation) {
        try { await capturer.stop(); } catch (e) {}
        try { await capturer.release(); } catch (e) {}
        return;
      }
      clearTimeout(this.timeout);
      const resolve = this.settleStart;
      this.settleStart = null;
      if (resolve !== null) resolve(true);
    } catch (e) { this.fail(generation, '麦克风不可用，请检查权限或使用文字输入。'); }
  }

  private async playReadyTone(): Promise<void> {
    const renderer = await audio.createAudioRenderer({
      streamInfo: { samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
        channels: audio.AudioChannel.CHANNEL_1, sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW },
      rendererInfo: { usage: audio.StreamUsage.STREAM_USAGE_MUSIC, rendererFlags: 0 }
    });
    try {
      const samples = new Int16Array(7200);
      for (let i = 0; i < samples.length; i++) {
        const envelope = Math.sin(Math.PI * i / samples.length);
        samples[i] = Math.round(5500 * envelope * Math.sin(2 * Math.PI * 880 * i / 48000));
      }
      await renderer.start();
      await renderer.write(samples.buffer);
      await renderer.drain();
    } finally {
      await renderer.release();
    }
  }

  private async stopCapture(): Promise<void> {
    const capturer = this.capturer;
    this.capturer = null;
    if (capturer === null) return;
    try { await capturer.stop(); } catch (e) {}
    try { await capturer.release(); } catch (e) {}
  }

  async finish(): Promise<void> {
    const generation = this.generation;
    if (!this.recording) return;
    this.recording = false;
    await this.stopCapture();
    if (generation !== this.generation || this.ws === null) return;
    if (this.bytesSent === 0) { this.fail(generation, '没有采集到音频，请重录或打字。'); return; }
    this.timeout = setTimeout(() => { this.fail(generation, '录音整理超时，未自动提交，可重录或打字。'); }, 15000);
    try { await this.ws.send('finish'); }
    catch (e) { this.fail(generation, '结束录音失败，请重试或打字。'); }
  }

  private fail(generation: number, message: string): void {
    if (generation !== this.generation) return;
    this.cancel();
    this.onError(message);
  }

  cancel(): void {
    this.generation++;
    this.busy = false;
    this.recording = false;
    clearTimeout(this.timeout);
    const resolve = this.settleStart;
    this.settleStart = null;
    if (resolve !== null) resolve(false);
    this.stopCapture();
    const ws = this.ws;
    this.ws = null;
    if (ws !== null) ws.close().catch(() => {});
  }
}

export class TtsPlayer {
  private player: media.AVPlayer | null = null;
  private file: fileIo.File | null = null;
  private generation: number = 0;
  private resolveStart: ((ok: boolean) => void) | null = null;
  private timeout: number = -1;

  private speed(rate: number): media.PlaybackSpeed {
    if (rate === 0.75) return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    if (rate === 1.25) return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    if (rate === 1.5) return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }

  private settle(ok: boolean): void {
    clearTimeout(this.timeout);
    const resolve = this.resolveStart;
    this.resolveStart = null;
    if (resolve !== null) resolve(ok);
  }

  async play(context: common.UIAbilityContext, path: string, rate: number = 1): Promise<boolean> {
    await this.stop();
    const generation = this.generation;
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      this.file = file;
      const player = await media.createAVPlayer();
      if (generation !== this.generation) { await player.release(); return false; }
      this.player = player;
      const ready = new Promise<boolean>((resolve) => { this.resolveStart = resolve; });
      this.timeout = setTimeout(() => { this.settle(false); this.stop(); }, 15000);
      player.on('error', () => { if (generation === this.generation) { this.settle(false); this.stop(); } });
      player.on('stateChange', (state: media.AVPlayerState) => {
        if (generation !== this.generation) return;
        hilog.info(0, 'nuanlinVoice', 'TTS state: %{public}s', state);
        if (state === 'initialized') {
          player.prepare().catch(() => { if (generation === this.generation) { this.settle(false); this.stop(); } });
        } else if (state === 'prepared') {
          try { player.setSpeed(this.speed(rate)); }
          catch (e) { this.settle(false); this.stop(); return; }
          player.play().then(() => { if (generation === this.generation) this.settle(true); })
            .catch(() => { if (generation === this.generation) { this.settle(false); this.stop(); } });
        } else if (state === 'completed') {
          this.stop();
        }
      });
      player.fdSrc = { fd: file.fd, offset: 0, length: fileIo.statSync(path).size };
      return await ready;
    } catch (e) { if (generation === this.generation) await this.stop(); return false; }
  }

  async stop(): Promise<void> {
    this.generation++;
    this.settle(false);
    const player = this.player;
    this.player = null;
    if (player !== null) {
      try { await player.release(); } catch (e) {}
    }
    const file = this.file;
    this.file = null;
    if (file !== null) {
      try { fileIo.closeSync(file); } catch (e) {}
    }
  }
}
