import { buffer } from '@kit.ArkTS';
import resourceManager from '@ohos.resourceManager';

export const LINUXDO_TAG_ICONS_RAWFILE = 'linuxdo_tag_icons.json';

export interface TagIconStyle {
  tagName: string;
  iconId: string;
  color: string;
}

interface RawTagIconStyle {
  tagName?: string;
  iconId?: string;
  color?: string;
}

const tagIconMap: Map<string, TagIconStyle> = new Map();
let tagIconsLoaded: boolean = false;

export function loadTagIconsFromRawContent(rawContent: Uint8Array): number {
  try {
    const json: string = buffer.from(rawContent as ArrayBufferLike).toString('utf8');
    return loadTagIconsFromJson(json);
  } catch (err) {
    tagIconMap.clear();
    tagIconsLoaded = true;
    return 0;
  }
}

export function loadTagIconsFromJson(json: string): number {
  let rawStyles: RawTagIconStyle[] = [];
  try {
    rawStyles = JSON.parse(json) as RawTagIconStyle[];
  } catch (err) {
    tagIconMap.clear();
    tagIconsLoaded = true;
    return 0;
  }

  tagIconMap.clear();

  if (!Array.isArray(rawStyles)) {
    tagIconsLoaded = true;
    return 0;
  }

  for (let index: number = 0; index < rawStyles.length; index++) {
    const style: TagIconStyle | undefined = normalizeRawStyle(rawStyles[index]);
    if (style) {
      tagIconMap.set(normalizeTagKey(style.tagName), style);
    }
  }

  tagIconsLoaded = true;
  return tagIconMap.size;
}

export function ensureTagIconsLoaded(manager: resourceManager.ResourceManager): number {
  if (tagIconsLoaded && tagIconMap.size > 0) {
    return tagIconMap.size;
  }

  try {
    const rawContent: Uint8Array = manager.getRawFileContentSync(LINUXDO_TAG_ICONS_RAWFILE);
    return loadTagIconsFromRawContent(rawContent);
  } catch (err) {
    tagIconMap.clear();
    tagIconsLoaded = true;
    return 0;
  }
}

export function getTagIconStyle(tagName: string): TagIconStyle | undefined {
  return tagIconMap.get(normalizeTagKey(tagName));
}

export function hasLoadedTagIcons(): boolean {
  return tagIconsLoaded;
}

function normalizeRawStyle(rawStyle: RawTagIconStyle): TagIconStyle | undefined {
  const tagName: string = normalizeText(rawStyle.tagName);
  const iconId: string = normalizeText(rawStyle.iconId);
  const color: string = normalizeText(rawStyle.color);
  if (tagName.length === 0 || iconId.length === 0) {
    return undefined;
  }

  return {
    tagName: tagName,
    iconId: iconId,
    color: color.length > 0 ? color : '#6B7280'
  };
}

function normalizeTagKey(tagName: string): string {
  return normalizeText(tagName).toLowerCase();
}

function normalizeText(value?: string): string {
  return value ? value.trim() : '';
}
