package com.hirehub.app

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryPurchasesParams
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val billingStatusChannel = "com.hirehub.app/subscription_status"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

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

	private fun queryGooglePlaySubscriptionState(
		productIds: Set<String>,
		result: MethodChannel.Result,
	) {
		val billingClient = BillingClient.newBuilder(this)
			.setListener { _: BillingResult, _: MutableList<Purchase>? -> }
			.enablePendingPurchases()
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
