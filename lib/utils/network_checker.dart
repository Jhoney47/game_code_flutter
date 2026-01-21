import 'dart:io';
import 'package:http/http.dart' as http;
import 'logger.dart';

/// 网络检测工具类
/// 
/// 功能：
/// - 检测网络连接状态
/// - 测试各数据源可用性
/// - DNS 解析检测
class NetworkChecker {
  /// 检测网络连接（快速检测）
  static Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('www.baidu.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      Logger.warning('网络连接检测失败', tag: 'NetworkChecker');
      return false;
    }
  }
  
  /// 测试数据源可用性
  static Future<Map<String, bool>> testDataSources(List<String> urls) async {
    final results = <String, bool>{};
    
    Logger.info('开始测试数据源可用性...', tag: 'NetworkChecker');
    
    for (final url in urls) {
      try {
        final uri = Uri.parse(url);
        final response = await http.head(uri).timeout(
          const Duration(seconds: 5),
        );
        
        final isAvailable = response.statusCode == 200 || response.statusCode == 304;
        results[url] = isAvailable;
        
        if (isAvailable) {
          Logger.success('✓ 数据源可用', tag: 'NetworkChecker');
          Logger.info('  URL: $url');
        } else {
          Logger.warning('✗ 数据源不可用 (${response.statusCode})', tag: 'NetworkChecker');
          Logger.info('  URL: $url');
        }
      } catch (e) {
        results[url] = false;
        Logger.error('✗ 数据源测试失败', tag: 'NetworkChecker', error: e);
        Logger.info('  URL: $url');
      }
    }
    
    final availableCount = results.values.where((v) => v).length;
    Logger.info('测试完成: $availableCount/${urls.length} 个数据源可用', tag: 'NetworkChecker');
    
    return results;
  }
  
  /// 测试 DNS 解析
  static Future<bool> testDNS(String hostname) async {
    try {
      final addresses = await InternetAddress.lookup(hostname)
          .timeout(const Duration(seconds: 3));
      
      if (addresses.isNotEmpty) {
        Logger.success('DNS 解析成功: $hostname', tag: 'NetworkChecker');
        for (final addr in addresses) {
          Logger.info('  IP: ${addr.address}');
        }
        return true;
      }
      return false;
    } catch (e) {
      Logger.error('DNS 解析失败: $hostname', tag: 'NetworkChecker', error: e);
      return false;
    }
  }
  
  /// 获取网络诊断信息
  static Future<Map<String, dynamic>> getDiagnostics() async {
    Logger.info('开始网络诊断...', tag: 'NetworkChecker');
    
    final diagnostics = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'connected': false,
      'dns': {},
      'dataSources': {},
    };
    
    // 检测基本连接
    diagnostics['connected'] = await isConnected();
    
    // 测试 DNS
    diagnostics['dns'] = {
      'cdn.jsdelivr.net': await testDNS('cdn.jsdelivr.net'),
      'raw.githubusercontent.com': await testDNS('raw.githubusercontent.com'),
      'cdn.statically.io': await testDNS('cdn.statically.io'),
    };
    
    Logger.info('网络诊断完成', tag: 'NetworkChecker');
    return diagnostics;
  }
}
