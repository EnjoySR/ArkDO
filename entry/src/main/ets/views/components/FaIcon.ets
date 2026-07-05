import { buffer } from '@kit.ArkTS';
import resourceManager from '@ohos.resourceManager';

export const LINUXDO_FA_SYMBOLS_RAWFILE = 'linuxdo_fa_symbols.json';

export interface FaIconDefinition {
  id: string;
  rawfilePath: string;
}

interface RawFaIconDefinition {
  id?: string;
}

const faIconMap: Map<string, FaIconDefinition> = new Map();
let faIconsLoaded: boolean = false;
const FALLBACK_FA_ICON_SIZE: number = 14;

export function loadFaIconsFromRawContent(rawContent: Uint8Array): number {
  try {
    const json: string = buffer.from(rawContent as ArrayBufferLike).toString('utf8');
    return loadFaIconsFromJson(json);
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }
}

export function loadFaIconsFromJson(json: string): number {
  let rawIcons: RawFaIconDefinition[] = [];
  try {
    rawIcons = JSON.parse(json) as RawFaIconDefinition[];
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }

  faIconMap.clear();

  if (!Array.isArray(rawIcons)) {
    faIconsLoaded = true;
    return 0;
  }

  for (let index: number = 0; index < rawIcons.length; index++) {
    const rawIcon: RawFaIconDefinition = rawIcons[index];
    const icon: FaIconDefinition | undefined = normalizeRawIcon(rawIcon);
    if (icon) {
      faIconMap.set(icon.id, icon);
    }
  }

  faIconsLoaded = true;
  return faIconMap.size;
}

export function ensureFaIconsLoaded(manager: resourceManager.ResourceManager): number {
  if (faIconsLoaded && faIconMap.size > 0) {
    return faIconMap.size;
  }

  try {
    const rawContent: Uint8Array = manager.getRawFileContentSync(LINUXDO_FA_SYMBOLS_RAWFILE);
    return loadFaIconsFromRawContent(rawContent);
  } catch (err) {
    faIconMap.clear();
    faIconsLoaded = true;
    return 0;
  }
}

export function getFaIcon(iconId: string): FaIconDefinition | undefined {
  return faIconMap.get(iconId);
}

export function hasLoadedFaIcons(): boolean {
  return faIconsLoaded;
}

function normalizeRawIcon(rawIcon: RawFaIconDefinition): FaIconDefinition | undefined {
  if (!rawIcon.id || rawIcon.id.trim().length === 0) {
    return undefined;
  }

  const iconId: string = rawIcon.id.trim();
  return {
    id: iconId,
    rawfilePath: `fa_icons/${iconId}.svg`
  };
}

@Component
export struct FaIconView {
  icon: FaIconDefinition = {
    id: '',
    rawfilePath: ''
  };
  color: string = '#6B7280';
  iconSize: number = FALLBACK_FA_ICON_SIZE;

  build() {
    Image($rawfile(this.icon.rawfilePath))
      .objectFit(ImageFit.Contain)
      .renderMode(ImageRenderMode.Template)
      .fillColor(this.color)
      .draggable(false)
      .width(this.getFrameSize())
      .height(this.getFrameSize())
  }

  private getFrameSize(): number {
    return this.iconSize > 0 ? this.iconSize : FALLBACK_FA_ICON_SIZE;
  }
}
