import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreData
import os.log

@main
struct MagicJourney: App {
    let persistenceController = PersistenceController.shared
    @StateObject var attractionsViewModel = AttractionsViewModel(context: PersistenceController.shared.container.viewContext)
    
    private let logger = Logger(subsystem: "com.magicjourney.app", category: "background_tasks")

    init() {
        MagicJourney.registerBackgroundTasks(logger: logger)
        requestNotificationPermission()
        
        // Planification initiale du rafraîchissement dès le lancement de l'application
        MagicJourney.scheduleAppRefresh(logger: logger)
    }

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    MagicJourney.scheduleProcessingTask(logger: logger)
                }
        }
    }

    private static func registerBackgroundTasks(logger: Logger) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.magicjourney.refresh", using: nil) { task in
            handleAppRefresh(task: task as! BGAppRefreshTask, logger: logger)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.magicjourney.processing", using: nil) { task in
            handleProcessingTask(task: task as! BGProcessingTask, logger: logger)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.magicjourney.sendAggregatedData", using: nil) { task in
            handleSendAggregatedDataTask(task: task as! BGProcessingTask, logger: logger)
        }

        logger.info("Background tasks registered successfully.")
    }


    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                logger.info("Notification permission granted.")
            } else if let error = error {
                logger.error("Failed to request notification permission: \(error.localizedDescription)")
            } else {
                logger.info("Notification permission denied.")
            }
        }
    }

    private static func scheduleProcessingTask(logger: Logger) {
        let request = BGProcessingTaskRequest(identifier: "app.magicjourney.processing")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Processing task scheduled successfully.")
        } catch {
            logger.error("Failed to schedule processing task: \(error.localizedDescription)")
        }
    }

    private static func scheduleAppRefresh(logger: Logger) {
        let request = BGAppRefreshTaskRequest(identifier: "app.magicjourney.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 300) // Toutes les 5 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("App refresh scheduled successfully.")
        } catch {
            logger.error("Failed to schedule app refresh: \(error.localizedDescription)")
        }
    }
    
    private static func handleProcessingTask(task: BGProcessingTask, logger: Logger) {
        DispatchQueue.global(qos: .background).async {
            logger.info("Starting background data processing.")

            let context = PersistenceController.shared.container.viewContext
            context.perform {
                let attractionsService = AttractionsService(viewContext: context)

                logger.info("Checking for changes in favorite attraction wait times.")
                attractionsService.fetchAndUpdateAttractions()
                logger.info("Data processing completed.")

                task.setTaskCompleted(success: true)
                scheduleProcessingTask(logger: logger)
            }
        }
    }
    
    private static func handleSendAggregatedDataTask(task: BGProcessingTask, logger: Logger) {
        DispatchQueue.global(qos: .background).async {
            logger.info("Starting sendAggregatedData task.")

            let context = PersistenceController.shared.container.viewContext
            context.perform {
                let attractionsService = AttractionsService(viewContext: context)
                attractionsService.sendAggregatedWaitTimesToAPI()
                logger.info("sendAggregatedData task completed.")

                task.setTaskCompleted(success: true)
            }
        }
    }


    private static func handleAppRefresh(task: BGAppRefreshTask, logger: Logger) {
        DispatchQueue.global(qos: .background).async {
            logger.info("Starting background data refresh.")

            let context = PersistenceController.shared.container.viewContext
            context.perform {
                let attractionsService = AttractionsService(viewContext: context)

                logger.info("Attempting to fetch and update attractions.")
                attractionsService.fetchAndUpdateAttractions()
                logger.info("Data refresh completed.")

                task.setTaskCompleted(success: true)
                
                // Replanification après chaque rafraîchissement
                scheduleAppRefresh(logger: logger)
            }
        }
    }
}
