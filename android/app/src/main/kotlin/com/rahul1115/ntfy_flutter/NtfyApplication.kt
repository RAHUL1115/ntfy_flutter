package com.rahul1115.ntfy_flutter

import android.app.Application
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network

class NtfyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val connectivity = getSystemService(ConnectivityManager::class.java)
        var skipInitialAvailable = connectivity.activeNetwork != null
        connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (skipInitialAvailable) {
                    skipInitialAvailable = false
                    return
                }
                if (!BackgroundListenerService.forceReconnectIfRunning(this@NtfyApplication)) {
                    BackgroundReconnectJobService.schedule(this@NtfyApplication)
                }
            }

            override fun onLost(network: Network) {
                skipInitialAvailable = false
                BackgroundListenerService.forceReconnectIfRunning(this@NtfyApplication)
            }
        })
    }
}

class BackgroundReconnectJobService : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        if (!BackgroundListenerService.isEnabled(this)) return false
        BackgroundListenerService.startOrRefresh(
            this,
            onRefreshed = { jobFinished(params, false) },
            onError = { jobFinished(params, true) },
        )
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean = true

    companion object {
        private const val JOB_ID = 9107

        fun schedule(context: Context) {
            val job = JobInfo.Builder(
                JOB_ID,
                ComponentName(context, BackgroundReconnectJobService::class.java),
            )
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(30_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .build()
            context.getSystemService(JobScheduler::class.java).schedule(job)
        }
    }
}

class BackgroundRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (
            intent.action == Intent.ACTION_BOOT_COMPLETED &&
            BackgroundListenerService.isEnabled(context)
        ) {
            BackgroundListenerService.startOrRefresh(context)
        }
    }
}
