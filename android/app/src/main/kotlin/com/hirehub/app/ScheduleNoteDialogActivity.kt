package com.hirehub.app

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

class ScheduleNoteDialogActivity : Activity() {
	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)

		val dateTitle = intent.getStringExtra(EXTRA_DATE_TITLE).orEmpty()
		val note = intent.getStringExtra(EXTRA_NOTE).orEmpty()

		AlertDialog.Builder(this)
			.setTitle(if (dateTitle.isBlank()) "Schedule Note" else dateTitle)
			.setMessage(note.ifBlank { "No note for this day." })
			.setPositiveButton(android.R.string.ok) { dialog, _ ->
				dialog.dismiss()
			}
			.setOnDismissListener { finish() }
			.show()
	}

	companion object {
		const val EXTRA_DATE_TITLE = "com.hirehub.app.EXTRA_DATE_TITLE"
		const val EXTRA_NOTE = "com.hirehub.app.EXTRA_NOTE"
	}
}
