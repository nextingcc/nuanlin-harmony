import { rcp } from '@kit.RemoteCommunicationKit';

export interface PatchReply {
  responseCode: number;
  result: string;
  cookies: string;
}

// API 22 的 NetworkKit HTTP 枚举不含 PATCH，使用原生 RCP 明确支持的方式。
export async function patchRequest(url: string, headers: Record<string, string>, body: string,
  timeout: number): Promise<PatchReply> {
  const session = rcp.createSession();
  try {
    const request = new rcp.Request(url, 'PATCH', headers, body);
    request.configuration = { transfer: { timeout: { connectMs: 8000, transferMs: timeout } } };
    const response = await session.fetch(request);
    const reply: PatchReply = { responseCode: response.statusCode, result: response.toString() ?? '', cookies: '' };
    return reply;
  } finally {
    session.close();
  }
}
