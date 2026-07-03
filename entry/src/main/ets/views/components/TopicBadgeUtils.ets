import { AppConstants } from '../../common/constants/AppConstants';
import { TopicCategory } from '../../models/Topic';
import { FaIconDefinition, getFaIcon } from './FaIcon';
import { getTagIconStyle, TagIconStyle } from './TagIconRegistry';

export function getCategoryIcon(category: TopicCategory, parentCategory?: TopicCategory): FaIconDefinition | undefined {
  const categoryIcon: FaIconDefinition | undefined = getCategoryIconByName(normalizeIconName(category.icon));
  if (categoryIcon) {
    return categoryIcon;
  }

  if (parentCategory) {
    return getCategoryIconByName(normalizeIconName(parentCategory.icon));
  }
  return undefined;
}

export function getTagIcon(tagName: string): FaIconDefinition | undefined {
  const style: TagIconStyle | undefined = getTagIconStyle(tagName);
  return style ? getFaIcon(style.iconId) : undefined;
}

export function getTagColor(tagName: string): string {
  const style: TagIconStyle | undefined = getTagIconStyle(tagName);
  return style ? style.color : '#6B7280';
}

export function getCategoryColor(category: TopicCategory): string {
  return `#${normalizeHex(category.color, '6B7280')}`;
}

export function getCategoryLogo(category: TopicCategory, parentCategory?: TopicCategory): string {
  if (category.uploadedLogo && category.uploadedLogo.length > 0) {
    return category.uploadedLogo;
  }
  if (parentCategory && parentCategory.uploadedLogo && parentCategory.uploadedLogo.length > 0) {
    return parentCategory.uploadedLogo;
  }
  return '';
}

export function resolveBadgeAssetUrl(rawUrl: string): string {
  if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
    return rawUrl;
  }
  if (rawUrl.startsWith('//')) {
    return `https:${rawUrl}`;
  }
  if (rawUrl.startsWith('/')) {
    return `${AppConstants.BASE_URL}${rawUrl}`;
  }
  return `${AppConstants.BASE_URL}/${rawUrl}`;
}

function getCategoryIconByName(name: string): FaIconDefinition | undefined {
  if (name.length === 0) {
    return undefined;
  }

  const directIcon: FaIconDefinition | undefined = getFaIcon(name);
  if (directIcon) {
    return directIcon;
  }

  let iconId: string = '';
  switch (name) {
    case 'file-code':
      iconId = 'code';
      break;
    case 'award':
    case 'medal':
    case 'trophy':
      iconId = 'trophy';
      break;
    case 'book-open-reader':
    case 'book-open':
    case 'book':
      iconId = 'book-open-reader';
      break;
    case 'seedling':
    case 'leaf':
      iconId = 'seedling';
      break;
    case 'file-lines':
    case 'doc':
    case 'newspaper':
      iconId = 'file-lines';
      break;
    case 'clone':
    case 'database':
    case 'server':
      iconId = 'hard-drive';
      break;
    case 'users':
    case 'user-group':
    case 'user':
      iconId = 'users';
      break;
    case 'megaphone':
      iconId = 'bullhorn';
      break;
    case 'comment':
      iconId = 'comments';
      break;
    default:
      iconId = '';
  }

  return iconId.length > 0 ? getFaIcon(iconId) : undefined;
}

function normalizeIconName(raw?: string): string {
  if (!raw) {
    return '';
  }

  const tokens: string[] = raw.trim().toLowerCase().split(/\s+/);
  let name: string = '';
  for (let index: number = 0; index < tokens.length; index++) {
    let token: string = tokens[index];
    if (token === 'fa-solid' || token === 'fa-regular' || token === 'fa-brands' ||
      token === 'fas' || token === 'far' || token === 'fab' || token === 'fa') {
      continue;
    }
    if (token.startsWith('fa-')) {
      token = token.substring(3);
    }
    name = token;
  }
  return name;
}

function normalizeHex(value: string | undefined, fallback: string): string {
  if (!value) {
    return fallback;
  }
  const normalized: string = value.replace('#', '').trim();
  return normalized.length > 0 ? normalized : fallback;
}
