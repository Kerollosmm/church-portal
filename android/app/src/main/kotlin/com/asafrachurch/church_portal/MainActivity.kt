package com.asafrachurch.church_portal

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {

    private val deviceChannelName = "church_portal/device"
    private val installerChannelName = "church_portal/installer"

    private val oemIntentTryLists = mapOf(
        "autostart_xiaomi" to listOf(
            "com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.miui.securitycenter/com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
        ),
        "battery_xiaomi" to listOf(
            "com.miui.powerkeeper/com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            "com.miui.securitycenter/com.miui.powerkeeper.ui.HiddenAppsConfigActivity"
        ),
        "autostart_oppo" to listOf(
            "com.coloros.safecenter/.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter/com.coloros.safecenter.permission.startup.FakeActivity",
            "com.coloros.safecenter/com.coloros.safecenter.permission.startupapp.StartupAppListActivity",
            "com.oplus.battery/.OplusBatteryMainActivity"
        ),
        "battery_oppo" to listOf(
            "com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.oplus.battery/.OplusBatteryMainActivity"
        ),
        "autostart_vivo" to listOf(
            "com.vivo.permissionmanager/.activity.BgStartUpManagerActivity",
            "com.iqoo.secure/.ui.phoneoptimize.AddWhiteListActivity",
            "com.iqoo.secure/.safeguard.PurviewTabActivity"
        ),
        "autostart_huawei" to listOf(
            "com.huawei.systemmanager/.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager/com.huawei.systemmanager.optimize.process.ProtectActivity"
        ),
        "battery_samsung" to listOf(
            "com.samsung.android.lool/com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.samsung.android.sm/com.samsung.android.sm.ui.battery.BatteryActivity"
        )
    )

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel A: church_portal/device
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> {
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "brand" to Build.BRAND,
                                "model" to Build.MODEL,
                                "sdkInt" to Build.VERSION.SDK_INT
                            )
                        )
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizationsInternal())
                    }
                    "openSettings" -> {
                        val action = call.argument<String>("action")
                        val component = call.argument<String>("component")
                        openSettingsInternal(action, component)
                        result.success(true)
                    }
                    "getDiagnostics" -> {
                        val isIgnoring = isIgnoringBatteryOptimizationsInternal()
                        val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                        val canScheduleExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && alarmManager != null) {
                            alarmManager.canScheduleExactAlarms()
                        } else {
                            true
                        }
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                        val notificationsAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
                        } else if (notificationManager != null) {
                            notificationManager.areNotificationsEnabled()
                        } else {
                            true
                        }
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "brand" to Build.BRAND,
                                "model" to Build.MODEL,
                                "sdkInt" to Build.VERSION.SDK_INT,
                                "isIgnoringBatteryOptimizations" to isIgnoring,
                                "canScheduleExactAlarms" to canScheduleExact,
                                "notificationsAllowed" to notificationsAllowed,
                                "pendingCount" to 0
                            )
                        )
                    }
                    "openOemSettings" -> {
                        val actionKey = call.argument<String>("actionKey") ?: call.argument<String>("action")
                        val handled = openOemAction(actionKey)
                        if (!handled) {
                            openAppDetailsSettings()
                        }
                        result.success(true)
                    }
                    "openAppSettings" -> {
                        openAppDetailsSettings()
                        result.success(true)
                    }
                    "scheduleTestAlarm" -> {
                        val minutes = call.argument<Int>("minutes") ?: 2
                        val mode = scheduleTestAlarmInternal(minutes)
                        if (mode == null) {
                            result.error("SCHEDULE_FAILED", "test alarm could not be scheduled", null)
                        } else {
                            result.success(mode)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Channel B: church_portal/installer
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // The FileProvider (`res/xml/update_paths.xml`) only shares `cacheDir/updates/`;
                    // Dart's `Directory.systemTemp` is the code-cache dir on Android, outside it.
                    "getCacheDir" -> result.success(cacheDir.absolutePath)
                    "supportedAbi" -> {
                        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "universal"
                        result.success(abi)
                    }
                    "canRequestPackageInstalls", "canRequestInstalls" -> {
                        val canRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(canRequest)
                    }
                    "openManageUnknownApps", "openUnknownSourcesSettings" -> {
                        openManageUnknownAppsInternal()
                        result.success(true)
                    }
                    "verifyApkSignature", "apkCertMatches" -> {
                        val filePath = call.argument<String>("filePath") ?: call.argument<String>("path")
                        val expectedCertSha256 = call.argument<String>("expectedCertSha256")
                            ?: call.argument<String>("certSha256")
                        if (filePath.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            result.success(verifyApkSignatureInternal(filePath, expectedCertSha256))
                        }
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath") ?: call.argument<String>("path")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "filePath is required", null)
                        } else {
                            try {
                                installApkInternal(filePath)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("INSTALL_ERROR", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizationsInternal(): Boolean {
        val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun openAppDetailsSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (_: Exception) {}
    }

    private fun openSettingsInternal(action: String?, component: String?) {
        try {
            if (!component.isNullOrBlank()) {
                val parts = component.split("/")
                if (parts.size == 2) {
                    val pkg = parts[0]
                    val cls = if (parts[1].startsWith(".")) pkg + parts[1] else parts[1]
                    val intent = Intent().setComponent(ComponentName(pkg, cls))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (intent.resolveActivity(packageManager) != null) {
                        startActivity(intent)
                        return
                    }
                }
            }
            if (!action.isNullOrBlank()) {
                val intent = Intent(action).apply {
                    if (action == Settings.ACTION_APPLICATION_DETAILS_SETTINGS ||
                        (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && action == Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)) {
                        data = Uri.parse("package:$packageName")
                    }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (intent.resolveActivity(packageManager) != null) {
                    startActivity(intent)
                    return
                }
            }
        } catch (_: Exception) {}
        openAppDetailsSettings()
    }

    private fun openOemAction(actionKey: String?): Boolean {
        if (actionKey.isNullOrBlank()) return false
        val candidates = oemIntentTryLists[actionKey] ?: listOf(actionKey)
        for (entry in candidates) {
            try {
                val parts = entry.split("/")
                if (parts.size == 2) {
                    val pkg = parts[0]
                    val cls = if (parts[1].startsWith(".")) pkg + parts[1] else parts[1]
                    val intent = Intent().setComponent(ComponentName(pkg, cls))
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (intent.resolveActivity(packageManager) != null) {
                        try {
                            startActivity(intent)
                            return true
                        } catch (e: Exception) {
                            // fallback to next candidate
                        }
                    }
                } else {
                    val intent = Intent(entry).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    if (intent.resolveActivity(packageManager) != null) {
                        try {
                            startActivity(intent)
                            return true
                        } catch (e: Exception) {
                            // fallback to next candidate
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        return false
    }

    private fun openManageUnknownAppsInternal() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
            } else {
                openAppDetailsSettings()
            }
        } catch (_: Exception) {
            openAppDetailsSettings()
        }
    }

    /** Schedules the diagnostic test alarm with the reminders' mode: `"exact"` when exact alarms are
     *  allowed, `"inexact"` (≈ ±10 min in Doze) otherwise; null when nothing could be scheduled. */
    private fun scheduleTestAlarmInternal(minutes: Int): String? {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return null
            val intent = Intent(this, TestAlarmReceiver::class.java)
            val pi = PendingIntent.getBroadcast(
                this,
                9999,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )
            val triggerAt = System.currentTimeMillis() + (minutes * 60 * 1000L)
            val exactAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alarmManager.canScheduleExactAlarms()
            } else {
                true
            }
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (exactAllowed) {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    "exact"
                } else {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    "inexact"
                }
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                "exact"
            }
        } catch (_: Exception) {
            return null
        }
    }

    private fun getInstalledCertificates(): List<ByteArray> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                val signingInfo = packageInfo.signingInfo ?: return emptyList()
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners.map { it.toByteArray() }
                } else {
                    signingInfo.signingCertificateHistory.map { it.toByteArray() }
                }
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
                @Suppress("DEPRECATION")
                packageInfo.signatures?.map { it.toByteArray() } ?: emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun getArchiveCertificates(filePath: String): List<ByteArray> {
        return try {
            val file = File(filePath)
            if (!file.exists()) return emptyList()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageArchiveInfo(filePath, PackageManager.GET_SIGNING_CERTIFICATES)
                val signingInfo = packageInfo?.signingInfo
                if (signingInfo != null) {
                    if (signingInfo.hasMultipleSigners()) {
                        signingInfo.apkContentsSigners.map { it.toByteArray() }
                    } else {
                        signingInfo.signingCertificateHistory.map { it.toByteArray() }
                    }
                } else {
                    @Suppress("DEPRECATION")
                    packageInfo?.signatures?.map { it.toByteArray() } ?: emptyList()
                }
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageArchiveInfo(filePath, PackageManager.GET_SIGNATURES)
                packageInfo?.applicationInfo?.let {
                    it.sourceDir = filePath
                    it.publicSourceDir = filePath
                }
                @Suppress("DEPRECATION")
                packageInfo?.signatures?.map { it.toByteArray() } ?: emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val md = MessageDigest.getInstance("SHA-256")
        return md.digest(bytes).joinToString("") { "%02X".format(it) }
    }

    private fun normalizeCertSha256(hex: String): String {
        return hex.replace(":", "").replace(" ", "").trim().uppercase()
    }

    private fun verifyApkSignatureInternal(filePath: String, expectedCertSha256: String?): Boolean {
        // Same signing key is not enough: the archive must be this app (not another app signed
        // with the same key), otherwise the installer would offer a different application.
        val archivePackage = try {
            packageManager.getPackageArchiveInfo(filePath, 0)?.packageName
        } catch (_: Exception) {
            null
        }
        if (archivePackage != packageName) {
            return false
        }
        val installedCerts = getInstalledCertificates()
        val archiveCerts = getArchiveCertificates(filePath)
        if (installedCerts.isEmpty() || archiveCerts.isEmpty()) {
            return false
        }

        val installedHashes = installedCerts.map { normalizeCertSha256(sha256Hex(it)) }
        val archiveHashes = archiveCerts.map { normalizeCertSha256(sha256Hex(it)) }

        val matchesInstalled = archiveHashes.any { it in installedHashes }
        val matchesExpected = if (!expectedCertSha256.isNullOrBlank()) {
            val normExpected = normalizeCertSha256(expectedCertSha256)
            archiveHashes.any { it == normExpected }
        } else {
            true
        }

        return matchesInstalled && matchesExpected
    }

    private fun installApkInternal(filePath: String) {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(this, "${packageName}.updates", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}

class TestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val channelId = "reminders"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Same id / name as the Dart channel (local_notifications_io.dart) so this does not rename it.
            val channel = NotificationChannel(
                channelId,
                "تذكيراتي",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "إشعارات التذكيرات بالقداسات والمناسبات"
            }
            nm.createNotificationChannel(channel)
        }

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pi = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        val notification = builder
            .setContentTitle("اختبار الإشعارات")
            .setContentText("وصلك الإشعار التجريبي بنجاح!")
            .setSmallIcon(R.drawable.ic_stat_seal)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build()

        nm.notify(9999, notification)
    }
}
