import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';

void main() {
  // 短句加句號不像講出來的話（「好。」），但長句的標點是規則檔一路要求的，
  // 這裡驗的是「短句去句號、長句一字不動」這個分界。
  group('stripShortSentencePeriod', () {
    test('不含句號未滿 5 個字時，砍掉尾端句號', () {
      expect(ZeroTypeController.stripShortSentencePeriod('好。'), '好');
      expect(ZeroTypeController.stripShortSentencePeriod('知道了。'), '知道了');
      expect(ZeroTypeController.stripShortSentencePeriod('OK.'), 'OK');
      // 剛好 4 個字：砍
      expect(ZeroTypeController.stripShortSentencePeriod('等一下我。'), '等一下我');
    });

    test('滿 5 個字就保留句號——門檻不含句號本身', () {
      expect(ZeroTypeController.stripShortSentencePeriod('我等一下到。'), '我等一下到。');
      expect(
          ZeroTypeController.stripShortSentencePeriod('今天天氣不錯。'), '今天天氣不錯。');
    });

    test('本來就沒有句號的短句原樣通過', () {
      expect(ZeroTypeController.stripShortSentencePeriod('好'), '好');
      expect(ZeroTypeController.stripShortSentencePeriod(''), '');
    });

    test('問號驚嘆號是語氣，不砍', () {
      expect(ZeroTypeController.stripShortSentencePeriod('真的？'), '真的？');
      expect(ZeroTypeController.stripShortSentencePeriod('太好了！'), '太好了！');
    });

    test('句中的句號不動，只看尾巴', () {
      expect(ZeroTypeController.stripShortSentencePeriod('a.b'), 'a.b');
    });
  });
}
