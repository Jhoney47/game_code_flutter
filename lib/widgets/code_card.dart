import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/game_code.dart';
import '../repositories/code_repository.dart';
import '../theme/app_theme.dart';

class CodeCard extends StatelessWidget {
  final GameCode code;
  final VoidCallback? onReported;

  const CodeCard({
    super.key,
    required this.code,
    this.onReported,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 根据isActive状态决定样式
    final isActive = code.isActive;
    final cardOpacity = isActive ? 1.0 : 0.5;
    final cardColor = isActive 
        ? (isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight)
        : (isDark ? AppTheme.surfaceDark.withOpacity(0.5) : AppTheme.surfaceLight.withOpacity(0.5));

    // 检查是否即将过期（7天内）
    final isExpiringSoon = _isExpiringSoon();
    final daysUntilExpiry = _getDaysUntilExpiry();

    return Opacity(
      opacity: cardOpacity,
      child: Card(
        color: cardColor,
        elevation: isExpiringSoon ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isExpiringSoon 
              ? BorderSide(color: AppTheme.warningColor, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 游戏名称和举报按钮
              Row(
                children: [
                  Expanded(
                    child: Text(
                      code.gameName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 举报按钮 (直接放在这里，不使用Positioned)
                  GestureDetector(
                    onTap: () => _showReportDialog(context),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 兑换码
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark 
                      ? AppTheme.backgroundDark 
                      : AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  code.code,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // 奖励描述
              Row(
                children: [
                  const Text('🎁', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      code.rewardDescription,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // 底部信息栏：类型标签 + 截止日期/警告 + 复制按钮
              Row(
                children: [
                  // 类型标签（永久/限时）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: code.codeType == 'permanent'
                          ? Colors.green.withOpacity(0.15)
                          : Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          code.codeType == 'permanent' ? '♾️' : '⏰',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          code.codeType == 'permanent' ? '永久' : '限时',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: code.codeType == 'permanent'
                                ? Colors.green[700]
                                : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // 截止日期或警告信息
                  Expanded(
                    child: _buildExpiryInfo(theme, isExpiringSoon, daysUntilExpiry, isActive),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // 一键复制按钮
                  ElevatedButton.icon(
                    onPressed: () => _copyToClipboard(context),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示举报对话框
  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('举报兑换码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '游戏：${code.gameName}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '兑换码：${code.code}',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            const Text('请选择举报原因：'),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.error_outline, color: Colors.red),
              title: const Text('兑换码无效'),
              subtitle: const Text('该兑换码无法使用或已被使用'),
              onTap: () {
                Navigator.pop(context);
                _submitReport(context, 'invalid');
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.schedule, color: Colors.orange),
              title: const Text('兑换码已过期'),
              subtitle: const Text('该兑换码已超过有效期'),
              onTap: () {
                Navigator.pop(context);
                _submitReport(context, 'expired');
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 提交举报
  Future<void> _submitReport(BuildContext context, String reportType) async {
    // 显示加载提示
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('正在提交举报...'),
          ],
        ),
        duration: Duration(seconds: 1),
      ),
    );

    final repository = CodeRepository();
    final success = await repository.submitReport(
      gameName: code.gameName,
      code: code.code,
      reportType: reportType,
    );

    if (context.mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text('举报成功！感谢您的反馈'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        
        // 调用回调
        onReported?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('举报失败，请稍后重试'),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  /// 构建截止日期/警告信息
  Widget _buildExpiryInfo(ThemeData theme, bool isExpiringSoon, int? daysUntilExpiry, bool isActive) {
    if (!isActive) {
      // 已过期
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 14, color: Colors.red),
            const SizedBox(width: 4),
            Text(
              '已过期',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.red[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    
    if (isExpiringSoon && daysUntilExpiry != null) {
      // 即将过期（7天内）- 黄色警告
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '⚠️ 还剩${daysUntilExpiry}天',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.amber[900],
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    
    if (code.expireDate != null && code.codeType != 'permanent') {
      // 普通限时（超过7天）- 蓝色显示截止日期
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 14, color: Colors.blue),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _formatExpiryDate(code.expireDate!),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    
    return const SizedBox.shrink();
  }

  /// 检查是否即将过期（7天内）
  bool _isExpiringSoon() {
    if (code.expireDate == null || code.codeType == 'permanent') {
      return false;
    }
    
    try {
      final expiry = DateTime.parse(code.expireDate!);
      final now = DateTime.now();
      final difference = expiry.difference(now).inDays;
      return difference >= 0 && difference <= 7;
    } catch (e) {
      return false;
    }
  }

  /// 获取距离过期的天数
  int? _getDaysUntilExpiry() {
    if (code.expireDate == null) return null;
    
    try {
      final expiry = DateTime.parse(code.expireDate!);
      final now = DateTime.now();
      return expiry.difference(now).inDays;
    } catch (e) {
      return null;
    }
  }

  /// 格式化截止日期
  String _formatExpiryDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  /// 复制兑换码到剪贴板
  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: code.code));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('已复制: ${code.code}'),
          ],
        ),
        backgroundColor: AppTheme.successColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
