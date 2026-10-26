package com.hou.relation_graph

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.speech.RecognitionService
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 语音识别诊断通道。
 *
 * 国产 ROM 上「没有可用语音识别服务」这个提示经常是误报，真实原因可能是
 * 权限没给、系统里根本没有注册标准 RecognitionService，或者厂商只做了
 * 私有语音助手（不响应 android.speech.RecognitionService）。
 *
 * 这里直接把系统里的实情问出来，省得靠猜。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linkmind/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "diagnose" -> result.success(diagnose())
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linkmind/installer")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android 8+ 要求用户单独给「允许安装未知应用」，
                    // 没给就直接调安装会被系统拦掉，所以先查一次。
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "openInstallPermissionSetting" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("NO_PATH", "缺少文件路径", null)
                            return@setMethodCallHandler
                        }
                        val error = installApk(path)
                        if (error == null) result.success(null) else result.error("INSTALL", error, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 调起系统安装界面。
     *
     * 不能直接把 file:// 路径交给安装器：Android 7 起会抛
     * FileUriExposedException，必须通过 FileProvider 授予临时读权限。
     *
     * @return null 表示已成功唤起系统界面；否则返回给用户看的原因。
     */
    private fun installApk(path: String): String? {
        val file = File(path)
        if (!file.exists()) return "安装包文件不存在，可能没下载完"
        if (file.length() < 1024) return "安装包只有 ${file.length()} 字节，明显不对"

        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (e: Exception) {
            return "无法把安装包交给系统安装器：${e.message}"
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            "这台手机上找不到安装器"
        } catch (e: SecurityException) {
            "没有安装权限，先去设置里允许本应用安装未知应用"
        } catch (e: Exception) {
            "唤起安装界面失败：${e.message}"
        }
    }

    private fun diagnose(): Map<String, Any?> {
        val out = HashMap<String, Any?>()
        out["sdkInt"] = Build.VERSION.SDK_INT
        out["manufacturer"] = Build.MANUFACTURER
        out["model"] = Build.MODEL

        // 标准通道可用性：SpeechRecognizer 内部就是查这个
        out["available"] = SpeechRecognizer.isRecognitionAvailable(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            out["onDeviceAvailable"] = SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        }

        // 列出所有注册成 RecognitionService 的服务（谁在提供识别能力）
        val services = ArrayList<Map<String, String>>()
        try {
            val intent = Intent(RecognitionService.SERVICE_INTERFACE)
            val resolved = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.queryIntentServices(
                    intent, PackageManager.ResolveInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentServices(intent, 0)
            }
            for (ri in resolved) {
                val si = ri.serviceInfo ?: continue
                val m = HashMap<String, String>()
                m["package"] = si.packageName
                m["service"] = si.name
                m["label"] = try {
                    si.loadLabel(packageManager).toString()
                } catch (e: Exception) {
                    si.packageName
                }
                services.add(m)
            }
        } catch (e: Exception) {
            out["queryError"] = e.toString()
        }
        out["services"] = services

        return out
    }
}
