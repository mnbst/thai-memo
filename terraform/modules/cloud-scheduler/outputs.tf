output "job_name" {
  description = "Cloud Scheduler job name"
  value       = google_cloud_scheduler_job.daily_sentence_generation.name
}

output "service_account_email" {
  description = "Cloud Scheduler service account email"
  value       = google_service_account.scheduler.email
}

output "job_schedule" {
  description = "Cloud Scheduler job schedule (cron format)"
  value       = google_cloud_scheduler_job.daily_sentence_generation.schedule
}

output "job_time_zone" {
  description = "Cloud Scheduler job time zone"
  value       = google_cloud_scheduler_job.daily_sentence_generation.time_zone
}
