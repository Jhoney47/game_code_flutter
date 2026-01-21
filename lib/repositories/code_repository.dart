import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game_code.dart';

class CodeRepository {
  // 多个数据源，按优先级排序
  static const List<String> _dataUrls = [
    // 优先使用 jsDelivr CDN（速度快，但可能被限制）
    'https://cdn.jsdelivr.net/gh/Jhoney47/GameCodeBase@main/GameCodeBase.json',
    
    // 备用：GitHub Raw（稳定性高）
    'https://raw.githubusercontent.com/Jhoney47/GameCodeBase/main/GameCodeBase.json',
    
    // 备用：Statically CDN（另一个 CDN 服务）
    'https://cdn.statically.io/gh/Jhoney47/GameCodeBase/main/GameCodeBase.json',
  ];

  // 缓存相关常量
  static const String _cacheKey = 'game_codes_cache';
  static const String _cacheTimeKey = 'game_codes_cache_time';
  static const Duration _cacheExpiry = Duration(hours: 6);

  /// 获取游戏兑换码数据
  /// 
  /// 关键特性：
  /// 1. 多数据源备用机制，提升可用性
  /// 2. 本地缓存，离线也能使用
  /// 3. 自动重试和错误恢复
  Future<GameCodeResponse> fetchGameCodes() async {
    try {
      print('🌐 开始获取游戏兑换码数据...');
      
      // 尝试从网络获取
      final response = await _fetchFromNetwork();
      
      // 成功后保存到缓存
      await _saveToCache(response);
      
      print('✅ 数据获取成功并已缓存');
      return response;
    } catch (e) {
      print('❌ 网络获取失败: $e');
      print('💾 尝试读取本地缓存...');
      
      // 网络失败，尝试读取缓存
      final cachedData = await _loadFromCache();
      
      if (cachedData != null) {
        print('✅ 使用缓存数据');
        return cachedData;
      }
      
      // 缓存也没有，抛出错误
      print('❌ 无可用数据');
      throw Exception('网络连接失败且无缓存数据。\n请检查网络连接后重试。');
    }
  }

  /// 从网络获取数据（多数据源重试）
  Future<GameCodeResponse> _fetchFromNetwork() async {
    Exception? lastError;
    
    // 依次尝试每个数据源
    for (int i = 0; i < _dataUrls.length; i++) {
      try {
        // 添加时间戳参数破除CDN缓存
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final url = Uri.parse('${_dataUrls[i]}?v=$timestamp');
        
        print('🔄 尝试数据源 ${i + 1}/${_dataUrls.length}');
        print('   URL: ${_dataUrls[i]}');
        
        // 发起HTTP GET请求
        final response = await http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'User-Agent': 'GameCode-Flutter-App/1.0',
          },
        ).timeout(
          const Duration(seconds: 10), // 缩短超时时间以快速切换
          onTimeout: () {
            throw Exception('请求超时');
          },
        );
        
        print('   HTTP状态码: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          // 解析UTF-8编码的JSON数据
          try {
            final jsonData = json.decode(utf8.decode(response.bodyBytes));
            
            // 验证JSON数据完整性
            if (jsonData == null || jsonData is! Map<String, dynamic>) {
              throw Exception('数据格式错误：返回的不是有效的JSON对象');
            }
            
            if (!jsonData.containsKey('games') || jsonData['games'] == null) {
              throw Exception('数据格式错误：缺少games字段');
            }
            
            print('✅ 数据源 ${i + 1} 获取成功，共 ${jsonData['totalCodes'] ?? 0} 个兑换码');
            
            return GameCodeResponse.fromJson(jsonData);
          } catch (e) {
            print('❌ JSON解析失败: $e');
            throw Exception('数据解析失败');
          }
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e) {
        print('❌ 数据源 ${i + 1} 失败: $e');
        lastError = e is Exception ? e : Exception(e.toString());
        
        // 如果不是最后一个数据源，继续尝试下一个
        if (i < _dataUrls.length - 1) {
          print('⏭️  切换到下一个数据源...');
          await Future.delayed(const Duration(milliseconds: 500)); // 短暂延迟
          continue;
        }
      }
    }
    
    // 所有数据源都失败
    throw lastError ?? Exception('所有数据源均无法访问');
  }

  /// 保存到本地缓存
  Future<void> _saveToCache(GameCodeResponse data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(data.toJson());
      
      await prefs.setString(_cacheKey, jsonString);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      
      print('💾 数据已保存到本地缓存');
    } catch (e) {
      print('⚠️  缓存保存失败: $e');
      // 缓存失败不影响主流程
    }
  }

  /// 从本地缓存读取
  Future<GameCodeResponse?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final jsonString = prefs.getString(_cacheKey);
      final cacheTime = prefs.getInt(_cacheTimeKey);
      
      if (jsonString == null || cacheTime == null) {
        print('💾 无缓存数据');
        return null;
      }
      
      // 检查缓存是否过期
      final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTime;
      final cacheAgeHours = (cacheAge / (1000 * 60 * 60)).round();
      
      print('💾 缓存年龄: $cacheAgeHours 小时');
      
      if (cacheAge > _cacheExpiry.inMilliseconds) {
        print('⚠️  缓存已过期（超过6小时）');
        // 即使过期也返回，总比没有数据好
      }
      
      final jsonData = json.decode(jsonString);
      return GameCodeResponse.fromJson(jsonData);
    } catch (e) {
      print('❌ 缓存读取失败: $e');
      return null;
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimeKey);
      print('🗑️  缓存已清除');
    } catch (e) {
      print('❌ 缓存清除失败: $e');
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

  /// 按游戏名称筛选兑换码
  List<GameCode> filterByGame(List<GameCode> codes, String? gameName) {
    if (gameName == null || gameName.isEmpty) {
      return codes;
    }
    return codes.where((code) => code.gameName == gameName).toList();
  }

  /// 按类型筛选兑换码
  List<GameCode> filterByType(List<GameCode> codes, String type) {
    if (type == 'all') return codes;
    return codes.where((code) => code.codeType == type).toList();
  }

  /// 按状态筛选兑换码
  List<GameCode> filterByStatus(List<GameCode> codes, bool activeOnly) {
    if (!activeOnly) return codes;
    return codes.where((code) => code.isActive).toList();
  }

  /// 搜索兑换码（按游戏名称或兑换码内容）
  List<GameCode> searchCodes(List<GameCode> codes, String query) {
    if (query.isEmpty) return codes;
    
    final lowerQuery = query.toLowerCase();
    return codes.where((code) {
      return code.gameName.toLowerCase().contains(lowerQuery) ||
          code.code.toLowerCase().contains(lowerQuery) ||
          code.rewardDescription.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 排序兑换码
  List<GameCode> sortCodes(List<GameCode> codes, String sortBy) {
    final sortedCodes = List<GameCode>.from(codes);

    switch (sortBy) {
      case 'latest':
        // 按发布日期降序（最新的在前）
        sortedCodes.sort((a, b) {
          if (a.publishDate == null) return 1;
          if (b.publishDate == null) return -1;
          return b.publishDate!.compareTo(a.publishDate!);
        });
        break;

      case 'reliability':
        // 按可信度降序（准确率最高的在前）
        sortedCodes.sort((a, b) => b.reliability.compareTo(a.reliability));
        break;

      case 'expiring':
        // 即将过期的在前，然后按过期时间升序
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
