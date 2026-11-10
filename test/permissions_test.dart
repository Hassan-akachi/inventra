import 'package:flutter_test/flutter_test.dart';
import 'package:inventra/features/account/membership.dart';

void main() {
  test('owner can do everything in every shop', () {
    const p = Permissions.owner;
    expect(p.canEditItems && p.canAdjustStock && p.canSeeCosts && p.canVoidSales, isTrue);
    expect(p.canUseShop('any'), isTrue);
  });

  test('staff without extras can sell but not see costs or edit', () {
    const p = Permissions(isOwner: false);
    expect(p.canEditItems, isFalse);
    expect(p.canSeeCosts, isFalse);
    expect(p.canVoidSales, isFalse);
    expect(p.canUseShop('shop1'), isTrue, reason: 'no shop list = all shops');
  });

  test('staff limited to shops and granted permissions', () {
    const p = Permissions(isOwner: false, granted: {'edit_items'}, shopIds: {'shop1'});
    expect(p.canEditItems, isTrue);
    expect(p.canAdjustStock, isFalse);
    expect(p.canUseShop('shop1'), isTrue);
    expect(p.canUseShop('shop2'), isFalse);
  });

  test('member permissions parse from JSON text', () {
    final m = Member.fromRow({
      'id': 'm1',
      'user_id': 'u1',
      'display_name': 'Ada',
      'role': 'staff',
      'permissions': '["view_costs"]',
      'shop_ids': '["s1","s2"]',
    });
    expect(m.permissions, {'view_costs'});
    expect(m.shopIds, {'s1', 's2'});
    expect(Member.fromRow({'id': 'x', 'permissions': 'not json'}).permissions, isEmpty);
  });
}
