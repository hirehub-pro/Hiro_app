package com.hirehub.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryPurchasesParams
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val billingStatusChannel = "com.hirehub.app/subscription_status"
	private val scheduleWidgetChannel = "com.hirehub.app/schedule_widget"
	private val videoPickerChannel = "com.hirehub.app/video_picker"
	private val videoPickerRequestCode = 4217
	private var pendingVideoPickerResult: MethodChannel.Result? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			videoPickerChannel,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"pickVideo" -> pickVideo(result)
				else -> result.notImplemented()
			}
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			scheduleWidgetChannel,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"updateScheduleWidget" -> {
					@Suppress("UNCHECKED_CAST")
					val snapshot = call.arguments as? Map<String, Any?>
					if (snapshot == null) {
						result.error("invalid-args", "Schedule widget snapshot is required", null)
						return@setMethodCallHandler
					}

					ScheduleWidgetProvider.saveSnapshot(this, snapshot)
					ScheduleWidgetProvider.updateAllWidgets(this)
					result.success(null)
				}

				else -> result.notImplemented()
			}
		}

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			billingStatusChannel,
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"getSubscriptionState" -> {
					val productIds =
						call.argument<List<String>>("productIds")?.toSet()?.filter { it.isNotBlank() }?.toSet()
							?: emptySet()

					if (productIds.isEmpty()) {
						result.error("invalid-args", "productIds is required", null)
						return@setMethodCallHandler
					}

					queryGooglePlaySubscriptionState(productIds, result)
				}

				else -> result.notImplemented()
			}
		}
	}

	override fun onActivityResult(
		requestCode: Int,
		resultCode: Int,
		data: Intent?,
	) {
		if (requestCode == videoPickerRequestCode) {
			val result = pendingVideoPickerResult
			pendingVideoPickerResult = null

			if (result == null) {
				super.onActivityResult(requestCode, resultCode, data)
				return
			}

			if (resultCode != Activity.RESULT_OK || data?.data == null) {
				result.error("cancelled", "Video selection was cancelled", null)
				return
			}

			try {
				val uri = data.data!!
				val displayName = displayNameFor(uri)
				val file = copyPickedVideoToCache(uri, displayName)
				result.success(
					mapOf(
						"path" to file.absolutePath,
						"name" to displayName,
					),
				)
			} catch (e: Exception) {
				result.error("copy-failed", e.localizedMessage, null)
			}
			return
		}

		super.onActivityResult(requestCode, resultCode, data)
	}

	private fun pickVideo(result: MethodChannel.Result) {
		if (pendingVideoPickerResult != null) {
			result.error("already-active", "A video picker is already open", null)
			return
		}

		pendingVideoPickerResult = result
		val intent = Intent(Intent.ACTION_PICK, MediaStore.Video.Media.EXTERNAL_CONTENT_URI).apply {
			type = "video/*"
		}

		try {
			startActivityForResult(intent, videoPickerRequestCode)
		} catch (e: Exception) {
			pendingVideoPickerResult = null
			result.error("picker-unavailable", e.localizedMessage, null)
		}
	}

	private fun displayNameFor(uri: Uri): String {
		contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
			val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
			if (nameIndex >= 0 && cursor.moveToFirst()) {
				val name = cursor.getString(nameIndex)
				if (!name.isNullOrBlank()) return name
			}
		}

		return "video_${System.currentTimeMillis()}.mp4"
	}

	private fun copyPickedVideoToCache(uri: Uri, displayName: String): File {
		val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
		val targetDir = File(cacheDir, "picked_videos").apply { mkdirs() }
		val target = File(targetDir, "${System.currentTimeMillis()}_$safeName")

		contentResolver.openInputStream(uri).use { input ->
			requireNotNull(input) { "Unable to open selected video" }
			target.outputStream().use { output ->
				input.copyTo(output)
			}
		}

		return target
	}

	private fun queryGooglePlaySubscriptionState(
		productIds: Set<String>,
		result: MethodChannel.Result,
	) {
		val billingClient = BillingClient.newBuilder(this)
			.setListener { _: BillingResult, _: MutableList<Purchase>? -> }
			.enablePendingPurchases(
				PendingPurchasesParams.newBuilder()
					.enableOneTimeProducts()
					.build(),
			)
			.build()

		billingClient.startConnection(
			object : BillingClientStateListener {
				override fun onBillingSetupFinished(billingResult: BillingResult) {
					if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
						result.error(
							"billing-setup-failed",
							"Billing setup failed: ${billingResult.debugMessage}",
							null,
						)
						billingClient.endConnection()
						return
					}

					val params = QueryPurchasesParams.newBuilder()
						.setProductType(BillingClient.ProductType.SUBS)
						.build()

					billingClient.queryPurchasesAsync(params) { queryResult, purchasesList ->
						try {
							if (queryResult.responseCode != BillingClient.BillingResponseCode.OK) {
								result.error(
									"query-failed",
									"Purchase query failed: ${queryResult.debugMessage}",
									null,
								)
								return@queryPurchasesAsync
							}

							val matchedPurchase = purchasesList
								.asSequence()
								.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
								.firstOrNull { purchase -> purchase.products.any { productIds.contains(it) } }

							if (matchedPurchase == null) {
								result.success(
									mapOf(
										"status" to "inactive",
										"productId" to null,
										"isAutoRenewing" to false,
									),
								)
								return@queryPurchasesAsync
							}

							val state = if (matchedPurchase.isAutoRenewing) {
								"active_renewing"
							} else {
								"active_canceled"
							}

							result.success(
								mapOf(
									"status" to state,
									"productId" to matchedPurchase.products.firstOrNull(),
									"isAutoRenewing" to matchedPurchase.isAutoRenewing,
									"purchaseToken" to matchedPurchase.purchaseToken,
									"orderId" to matchedPurchase.orderId,
								),
							)
						} finally {
							billingClient.endConnection()
						}
					}
				}

				override fun onBillingServiceDisconnected() {
					result.error("billing-disconnected", "Billing service disconnected", null)
					billingClient.endConnection()
				}
			},
		)
	}
}
