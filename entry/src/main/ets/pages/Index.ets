import { HomePage } from '../views/pages/HomePage';

@Entry
@Component
struct Index {
  build() {
    Column() {
      HomePage()
    }
    .width('100%')
    .height('100%')
  }
}
