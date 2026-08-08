import 'package:flutter_test/flutter_test.dart';
import 'package:zero_type/core/controllers/zero_type_controller.dart';

void main() {
  // 第二段模型偶爾在短句尾巴憑空補 `_`，提示詞壓不掉，所以在程式這層砍。
  // 這裡驗的是「砍幻覺、但不吃掉使用者真的講出來的底線」這個分界。
  group('stripPhantomUnderscore', () {
    test('逐字稿沒有底線時，砍掉尾巴憑空冒出來的底線', () {
      expect(ZeroTypeController.stripPhantomUnderscore('天使多情_', '天使多情'),
          '天使多情');
      expect(ZeroTypeController.stripPhantomUnderscore('天使多情 _', '天使多情'),
          '天使多情');
      expect(ZeroTypeController.stripPhantomUnderscore('天使多情__', '天使多情'),
          '天使多情');
    });

    test('逐字稿本來就有底線時一律不動——那是使用者真的講的', () {
      expect(ZeroTypeController.stripPhantomUnderscore('file_name_', 'file_name_'),
          'file_name_');
      expect(ZeroTypeController.stripPhantomUnderscore('a_b _', 'a_b'), 'a_b _');
    });

    test('句中的底線不砍，只砍尾巴', () {
      expect(ZeroTypeController.stripPhantomUnderscore('前_後', '前後'), '前_後');
    });

    test('正常輸出原樣通過', () {
      expect(ZeroTypeController.stripPhantomUnderscore('今天天氣不錯。', '今天天氣不錯'),
          '今天天氣不錯。');
    });
  });
}
