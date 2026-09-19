import { createLogger } from '../common/utils/Logger';
import { pixiv } from '../services/PixivService';
import { NovelSeriesDetail, PixivNovel } from '../services/PixivTypes';

const logger = createLogger('NovelSeriesVM');


@ObservedV2
export class NovelSeriesViewModel {
  @Trace seriesDetail: NovelSeriesDetail | null = null;
  @Trace novels: PixivNovel[] = [];
  @Trace isLoading: boolean = true;
  @Trace isLoadingMore: boolean = false;
  @Trace isError: boolean = false;

  private seriesId: number = 0;
  private nextUrl: string | null = null;

  constructor(seriesId: number) {
    this.seriesId = seriesId;
    logger.info(`Constructor created with seriesId: ${seriesId}`);
  }

  async fetch() {
    this.isLoading = true;
    this.isError = false;
    try {
      const res = await pixiv.novelSeries(this.seriesId);
      this.seriesDetail = res.novel_series_detail || null;
      this.novels = res.novels || [];
      this.nextUrl = res.next_url || null;
    } catch (e) {
      logger.error('fetch error:', e);
      this.isError = true;
    } finally {
      this.isLoading = false;
    }
  }

  async loadMore() {
    if (!this.nextUrl || this.isLoadingMore || this.isLoading) return;
    this.isLoadingMore = true;
    try {
      const res = await pixiv.novelSeries(this.seriesId, this.nextUrl);
      this.novels = this.novels.concat(res.novels || []);
      this.nextUrl = res.next_url || null;
    } catch (e) {
      logger.error('loadMore error:', e);
    } finally {
      this.isLoadingMore = false;
    }
  }

  get hasMore(): boolean {
    return this.nextUrl !== null;
  }

}
