import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_code.dart';
import '../utils/logger.dart';
import '../utils/network_checker.dart';

class CodeRepository {
  // 多个数据源，优先使用国内可访问的源
  static const List<Map<String, String>> _dataSources = [
    {
      'name': 'GitHub Raw',
      'url': 'https://raw.githubusercontent.com/Jhoney47/GameCodeBase/main/GameCodeBase.json',
      'description': '稳定性高，国内部分地区可直接访问',
    },
    {
      'name': 'jsDelivr CDN',
      'url': 'https://cdn.jsdelivr.net/gh/Jhoney47/GameCodeBase@main/GameCodeBase.json',
      'description': '速度快，但部分地区可能被限制',
    },
    {
      'name': 'Statically CDN',
      'url': 'https://cdn.statically.io/gh/Jhoney47/GameCodeBase/main/GameCodeBase.json',
      'description': '备用 CDN 服务',
    },
  ];

  // 缓存相关常量
  static const String _cacheKey = 'game_codes_cache';
  static const String _cacheTimeKey = 'game_codes_cache_time';
  static const String _lastSuccessSourceKey = 'last_success_source';
  static const Duration _cacheExpiry = Duration(hours: 6);

  /// 获取游戏兑换码数据
  /// 
  /// 核心特性：
  /// 1. 智能数据源选择（优先使用上次成功的源）
  /// 2. 强制刷新模式（绕过缓存，破除 CDN 缓存）
  /// 3. 完整的错误处理和日志记录
  /// 4. 自动降级到缓存数据
  Future<GameCodeResponse> fetchGameCodes({bool forceRefresh = false}) async {
    final startTime = DateTime.now();
    Logger.info('========== 开始获取数据 ==========');
    Logger.info('强制刷新: $forceRefresh');
    Logger.deviceInfo();
    
    try {
      // 检查网络连接
      final isConnected = await NetworkChecker.isConnected();
      if (!isConnected) {
        Logger.warning('网络未连接，尝试使用缓存');
        return await _loadFromCacheOrThrow();
      }
      
      // 尝试从网络获取
      final response = await _fetchFromNetwork(forceRefresh: forceRefresh);
      
      // 成功后保存到缓存
      await _saveToCache(response);
      
      final duration = DateTime.now().difference(startTime);
      Logger.performance('数据获取', duration);
      Logger.success('========== 数据获取成功 ==========');
      
      return response;
    } catch (e, stackTrace) {
      Logger.error('网络获取失败，尝试使用缓存', error: e, stackTrace: stackTrace);
      
      // 网络失败，尝试读取缓存
      return await _loadFromCacheOrThrow();
    }
  }

  /// 从网络获取数据（智能多数据源重试）
  Future<GameCodeResponse> _fetchFromNetwork({bool forceRefresh = false}) async {
    Exception? lastError;
    
    // 获取上次成功的数据源索引
    final lastSuccessIndex = await _getLastSuccessSourceIndex();
    
    // 重新排序数据源：上次成功的放在最前面
    final orderedSources = _reorderDataSources(lastSuccessIndex);
    
    Logger.info('数据源顺序（共 ${orderedSources.length} 个）:');
    for (int i = 0; i < orderedSources.length; i++) {
      final source = orderedSources[i];
      Logger.info('  ${i + 1}. ${source['name']} ${i == 0 ? '⭐' : ''}');
    }
    
    // 依次尝试每个数据源
    for (int i = 0; i < orderedSources.length; i++) {
      final source = orderedSources[i];
      final sourceName = source['name']!;
      final sourceUrl = source['url']!;
      
      try {
        Logger.info('');
        Logger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        Logger.info('尝试数据源 ${i + 1}/${orderedSources.length}: $sourceName');
        Logger.info('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        
        // 构建 URL（强制刷新时添加时间戳破除缓存）
        String finalUrl = sourceUrl;
        if (forceRefresh) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final separator = sourceUrl.contains('?') ? '&' : '?';
          finalUrl = '$sourceUrl${separator}t=$timestamp';
          Logger.info('添加时间戳破除缓存: t=$timestamp');
        }
        
        final uri = Uri.parse(finalUrl);
        Logger.network('发起请求', url: finalUrl);
        
        // 发起 HTTP GET 请求
        final requestStart = DateTime.now();
        final response = await http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': forceRefresh ? 'no-cache, no-store, must-revalidate' : 'no-cache',
            'Pragma': 'no-cache',
            'User-Agent': 'GameCode-Flutter-App/1.0 (${Platform.operatingSystem})',
          },
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('请求超时', const Duration(seconds: 10));
          },
        );
        
        final requestDuration = DateTime.now().difference(requestStart);
        Logger.performance('HTTP 请求', requestDuration);
        Logger.network('收到响应', statusCode: response.statusCode);
        
        if (response.statusCode == 200) {
          // 解析 JSON
          final parseStart = DateTime.now();
          final gameData = await _parseResponse(response);
          final parseDuration = DateTime.now().difference(parseStart);
          Logger.performance('JSON 解析', parseDuration);
          
          // 保存成功的数据源索引
          await _saveLastSuccessSourceIndex(
            _dataSources.indexWhere((s) => s['url'] == sourceUrl)
          );
          
          Logger.success('✓ 数据源 ${i + 1} 获取成功');
          Logger.info('  游戏数量: ${gameData.games.length}');
          Logger.info('  兑换码总数: ${gameData.totalCodes}');
          
          return gameData;
        } else if (response.statusCode == 304) {
          Logger.info('数据未修改 (304)，使用缓存');
          final cached = await _loadFromCache();
          if (cached != null) {
            return cached;
          }
          throw Exception('304 响应但无缓存数据');
        } else {
          throw HttpException(
            '服务器返回错误: ${response.statusCode}',
            uri: uri,
          );
        }
      } on TimeoutException catch (e) {
        Logger.warning('✗ 数据源 ${i + 1} 超时');
        lastError = Exception('请求超时: ${e.message}');
      } on SocketException catch (e) {
        Logger.warning('✗ 数据源 ${i + 1} 连接失败');
        Logger.error('Socket 错误', error: e);
        lastError = Exception('网络连接失败: ${e.message}');
      } on HttpException catch (e) {
        Logger.warning('✗ 数据源 ${i + 1} HTTP 错误');
        Logger.error('HTTP 错误', error: e);
        lastError = e;
      } on FormatException catch (e) {
        Logger.error('✗ 数据源 ${i + 1} JSON 解析失败', error: e);
        lastError = Exception('数据格式错误: ${e.message}');
      } catch (e, stackTrace) {
        Logger.error('✗ 数据源 ${i + 1} 未知错误', error: e, stackTrace: stackTrace);
        lastError = e is Exception ? e : Exception(e.toString());
      }
      
      // 如果不是最后一个数据源，短暂延迟后继续
      if (i < orderedSources.length - 1) {
        Logger.info('⏭️  切换到下一个数据源...');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
    
    // 所有数据源都失败
    Logger.error('所有数据源均无法访问');
    throw lastError ?? Exception('所有数据源均无法访问，请检查网络连接');
  }

  /// 解析 HTTP 响应
  Future<GameCodeResponse> _parseResponse(http.Response response) async {
    try {
      // 检查 Content-Type
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('json') && !contentType.contains('text')) {
        Logger.warning('响应 Content-Type 不是 JSON: $contentType');
      }
      
      // 解析 UTF-8 编码的 JSON
      final jsonData = json.decode(utf8.decode(response.bodyBytes));
      
      // 验证 JSON 数据完整性
      if (jsonData == null || jsonData is! Map<String, dynamic>) {
        throw const FormatException('返回的不是有效的 JSON 对象');
      }
      
      if (!jsonData.containsKey('games') || jsonData['games'] == null) {
        throw const FormatException('缺少 games 字段');
      }
      
      if (jsonData['games'] is! List) {
        throw const FormatException('games 字段不是数组');
      }
      
      Logger.success('JSON 数据验证通过');
      
      return GameCodeResponse.fromJson(jsonData);
    } catch (e) {
      Logger.error('JSON 解析失败', error: e);
      // 记录原始响应的前 200 个字符用于调试
      final preview = response.body.length > 200 
          ? '${response.body.substring(0, 200)}...' 
          : response.body;
      Logger.info('响应预览: $preview');
      rethrow;
    }
  }

  /// 重新排序数据源（上次成功的放最前面）
  List<Map<String, String>> _reorderDataSources(int lastSuccessIndex) {
    if (lastSuccessIndex < 0 || lastSuccessIndex >= _dataSources.length) {
      return List.from(_dataSources);
    }
    
    final reordered = <Map<String, String>>[];
    reordered.add(_dataSources[lastSuccessIndex]);
    
    for (int i = 0; i < _dataSources.length; i++) {
      if (i != lastSuccessIndex) {
        reordered.add(_dataSources[i]);
      }
    }
    
    return reordered;
  }

  /// 获取上次成功的数据源索引
  Future<int> _getLastSuccessSourceIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_lastSuccessSourceKey) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 保存成功的数据源索引
  Future<void> _saveLastSuccessSourceIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSuccessSourceKey, index);
      Logger.cache('已保存成功的数据源索引: $index');
    } catch (e) {
      Logger.warning('保存数据源索引失败', tag: 'Cache');
    }
  }

  /// 保存到本地缓存
  Future<void> _saveToCache(GameCodeResponse data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(data.toJson());
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      final sizeKB = (jsonString.length / 1024).toStringAsFixed(2);
      Logger.cache('数据已缓存 (${sizeKB}KB)');
    } catch (e) {
      Logger.warning('缓存保存失败', tag: 'Cache');
      Logger.error('', error: e);
    }
  }

  /// 从本地缓存读取
  Future<GameCodeResponse?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonString = prefs.getString(_cacheKey);
      final cacheTime = prefs.getInt(_cacheTimeKey);
      
      if (jsonString == null || cacheTime == null) {
        Logger.cache('无缓存数据');
        return null;
      }
      
      // 计算缓存年龄
      final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTime;
      final cacheAgeHours = (cacheAge / (1000 * 60 * 60)).toStringAsFixed(1);
      final isExpired = cacheAge > _cacheExpiry.inMilliseconds;
      
      Logger.cache('缓存年龄: ${cacheAgeHours}小时 ${isExpired ? '(已过期)' : '(有效)'}');
      
      // 即使过期也返回，总比没有数据好
      if (isExpired) {
        Logger.warning('使用过期缓存数据');
      }
      
      final jsonData = json.decode(jsonString);
      return GameCodeResponse.fromJson(jsonData);
    } catch (e) {
      Logger.error('缓存读取失败', error: e);
      return null;
    }
  }

  /// 从缓存加载或抛出异常
  Future<GameCodeResponse> _loadFromCacheOrThrow() async {
    final cachedData = await _loadFromCache();
    
    if (cachedData != null) {
      Logger.success('使用缓存数据');
      return cachedData;
    }
    
    throw Exception('网络连接失败且无缓存数据。\n请检查网络连接后重试。');
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      await prefs.remove(_lastSuccessSourceKey);
      Logger.cache('缓存已清除');
    } catch (e) {
      Logger.error('缓存清除失败', error: e);
    }
  }

  /// 获取缓存信息
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheTime = prefs.getInt(_cacheTimeKey);
      
      if (cacheTime == null) {
        return {
          'hasCache': false,
          'cacheTime': null,
          'cacheAge': null,
          'isExpired': true,
        };
      }
      
      final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTime;
      final isExpired = cacheAge > _cacheExpiry.inMilliseconds;
      
      return {
        'hasCache': true,
        'cacheTime': DateTime.fromMillisecondsSinceEpoch(cacheTime),
        'cacheAge': Duration(milliseconds: cacheAge),
        'isExpired': isExpired,
      };
    } catch (e) {
      return {
        'hasCache': false,
        'error': e.toString(),
      };
    }
  }

  /// 测试所有数据源
  Future<Map<String, bool>> testAllDataSources() async {
    final urls = _dataSources.map((s) => s['url']!).toList();
    return await NetworkChecker.testDataSources(urls);
  }

  // ========== 筛选和排序方法（保持不变） ==========

  List<GameCode> filterByGame(List<GameCode> codes, String? gameName) {
    if (gameName == null || gameName.isEmpty) {
      return codes;
    }
    return codes.where((code) => code.gameName == gameName).toList();
  }

  List<GameCode> filterByType(List<GameCode> codes, String type) {
    if (type == 'all') return codes;
    return codes.where((code) => code.codeType == type).toList();
  }

  List<GameCode> filterByStatus(List<GameCode> codes, bool activeOnly) {
    if (!activeOnly) return codes;
    return codes.where((code) => code.isActive).toList();
  }

  List<GameCode> searchCodes(List<GameCode> codes, String query) {
    if (query.isEmpty) return codes;
    
    final lowerQuery = query.toLowerCase();
    return codes.where((code) {
      return code.gameName.toLowerCase().contains(lowerQuery) ||
          code.code.toLowerCase().contains(lowerQuery) ||
          code.rewardDescription.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  List<GameCode> sortCodes(List<GameCode> codes, String sortBy) {
    final sortedCodes = List<GameCode>.from(codes);

    switch (sortBy) {
      case 'latest':
        sortedCodes.sort((a, b) {
          if (a.publishDate == null) return 1;
          if (b.publishDate == null) return -1;
          return b.publishDate!.compareTo(a.publishDate!);
        });
        break;

      case 'reliability':
        sortedCodes.sort((a, b) => b.reliability.compareTo(a.reliability));
        break;

      case 'expiring':
        sortedCodes.sort((a, b) {
          if (a.expireDate == null && b.expireDate == null) return 0;
          if (a.expireDate == null) return 1;
          if (b.expireDate == null) return -1;
          return a.expireDate!.compareTo(b.expireDate!);
        });
        break;

      default:
        break;
    }

    return sortedCodes;
  }
}
