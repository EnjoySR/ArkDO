import { UserActivityItem, UserProfileDetail, UserSummary } from '../../models/UserProfile';

// 个人中心数据的应用级内存缓存,按用户名分键。
//
// 策略是 stale-while-revalidate:ProfilePage 每次 push 都是新实例,进入时先用缓存
// 秒出上次数据(无转圈),同时后台照常请求,成功后原地更新界面并回写缓存。
// 不设 TTL——反正每次进入都会后台刷新,缓存只负责撑起首屏。
export class UserProfileCache {
  private static detailMap: Map<string, UserProfileDetail> = new Map();
  private static summaryMap: Map<string, UserSummary> = new Map();
  private static activityMap: Map<string, UserActivityItem[]> = new Map();

  static getDetail(username: string): UserProfileDetail | undefined {
    return UserProfileCache.detailMap.get(username);
  }

  static setDetail(username: string, detail: UserProfileDetail): void {
    UserProfileCache.detailMap.set(username, detail);
  }

  static getSummary(username: string): UserSummary | undefined {
    return UserProfileCache.summaryMap.get(username);
  }

  static setSummary(username: string, summary: UserSummary): void {
    UserProfileCache.summaryMap.set(username, summary);
  }

  static getActivity(username: string): UserActivityItem[] | undefined {
    return UserProfileCache.activityMap.get(username);
  }

  static setActivity(username: string, activity: UserActivityItem[]): void {
    UserProfileCache.activityMap.set(username, activity);
  }

  // 仅供单测复位。
  static resetForTest(): void {
    UserProfileCache.detailMap.clear();
    UserProfileCache.summaryMap.clear();
    UserProfileCache.activityMap.clear();
  }
}
