import type { PlatformId } from '../domain/platform';

const MOBILE_USER_AGENT_REGEX = /Android|iPhone|iPad/i;

function detectMacPlatform(): PlatformId {
  try {
    const canvas = document.createElement('canvas');
    const gl =
      canvas.getContext('webgl') ??
      (canvas.getContext('experimental-webgl') as WebGLRenderingContext | null);
    const ext = gl?.getExtension('WEBGL_debug_renderer_info');
    const renderer = ext ? (gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) as string) : '';
    return renderer.includes('Intel') ? 'macos-intel' : 'macos-silicon';
  } catch {
    return 'macos-silicon';
  }
}

export function detectPlatform(userAgent: string): PlatformId | null {
  if (userAgent.includes('Win')) {
    return 'windows';
  }

  if (userAgent.includes('Mac')) {
    return detectMacPlatform();
  }

  if (!MOBILE_USER_AGENT_REGEX.test(userAgent)) {
    return 'linux';
  }

  return null;
}
