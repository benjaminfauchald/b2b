// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import CsvUploadController from "controllers/csv_upload_controller"

// Manually register the CSV upload controller
application.register("csv-upload", CsvUploadController)

eagerLoadControllersFrom("controllers", application)
