import 'dart:io';
import 'package:flutter/foundation.dart';

/// 日志工具类
/// 
/// 功能：
/// - 统一的日志输出格式
/// - 根据环境自动启用/禁用日志
/// - 支持不同日志级别
class Logger {
  static const String _tag = 'GameCode';
  
  /// 是否启用日志（Release 模式下自动禁用）
  static bool get isEnabled => kDebugMode;
  
  /// 信息日志（一般信息）
  static void info(String message, {String? tag}) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] ℹ️ ${tag ?? _tag}: $message');
  }
  
  /// 成功日志
  static void success(String message, {String? tag}) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] ✅ ${tag ?? _tag}: $message');
  }
  
  /// 警告日志
  static void warning(String message, {String? tag}) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] ⚠️ ${tag ?? _tag}: $message');
  }
  
  /// 错误日志
  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] ❌ ${tag ?? _tag}: $message');
    if (error != null) {
      print('   错误类型: ${error.runtimeType}');
      print('   错误详情: $error');
    }
    if (stackTrace != null) {
      print('   堆栈跟踪: ${stackTrace.toString().split('\n').take(5).join('\n   ')}');
    }
  }
  
  /// 网络请求日志
  static void network(String message, {String? url, int? statusCode, String? tag}) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    final status = statusCode != null ? ' [$statusCode]' : '';
    print('[$timestamp] 🌐 ${tag ?? _tag}$status: $message');
    if (url != null) {
      print('   URL: $url');
    }
  }
  
  /// 缓存操作日志
  static void cache(String message) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] 💾 ${_tag}: $message');
  }
  
  /// 性能日志
  static void performance(String operation, Duration duration) {
    if (!isEnabled) return;
    final timestamp = DateTime.now().toString().substring(11, 23);
    final ms = duration.inMilliseconds;
    final emoji = ms < 1000 ? '⚡' : ms < 3000 ? '🐢' : '🐌';
    print('[$timestamp] $emoji ${_tag}: $operation 耗时 ${ms}ms');
  }
  
  /// 设备信息日志
  static void deviceInfo() {
    if (!isEnabled) return;
    info('设备信息:');
    print('   平台: ${Platform.operatingSystem}');
    print('   版本: ${Platform.operatingSystemVersion}');
    print('   语言: ${Platform.localeName}');
  }
}
