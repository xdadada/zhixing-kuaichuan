import 'package:flutter_test/flutter_test.dart';
import 'package:lan_drop/models/device.dart';

void main() {
  group('Device.fromJson IP 优先级', () {
    const json = {
      'fingerprint': 'fp-1',
      'alias': 'LAPTOP-OV0F550G',
      'deviceType': 'desktop',
      'ip': '192.168.100.103', // 对方自报的旧 IP
      'port': 54322,
    };

    test('带 observedIp 时优先于自报 ip(对方广播过期 IP 的场景)', () {
      final d = Device.fromJson(json, observedIp: '192.168.100.100');
      expect(d, isNotNull);
      expect(d!.ip, '192.168.100.100');
      // 其余字段仍取自报值
      expect(d.alias, 'LAPTOP-OV0F550G');
      expect(d.port, 54322);
    });

    test('无 observedIp 时回退到自报 ip(从持久化恢复手动设备)', () {
      final d = Device.fromJson(json);
      expect(d, isNotNull);
      expect(d!.ip, '192.168.100.103');
    });

    test('两者都缺时解析失败', () {
      final d = Device.fromJson({
        'fingerprint': 'fp-1',
        'alias': 'x',
        'port': 54322,
      });
      expect(d, isNull);
    });
  });
}
