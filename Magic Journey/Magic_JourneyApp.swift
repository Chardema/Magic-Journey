import SwiftUI
import BackgroundTasks
import UserNotifications
import CoreData

@main
struct MagicJourney: App {
    let persistenceController = PersistenceController.shared
    @StateObject var attractionsViewModel = AttractionsViewModel(context: PersistenceController.shared.container.viewContext)

    init() {
        MagicJourney.registerBackgroundTasks()
        requestNotificationPermission()
    }

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    MagicJourney.scheduleAppRefresh()
                }
        }
    }

    private static func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.magicjourney.refresh", using: nil) { task in
            handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.magicjourney.sendAggregatedData", using: nil) { task in
            handleSendAggregatedDataTask(task: task as! BGAppRefreshTask)
        }
        logMessage("Tâches en arrière-plan enregistrées.")
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                MagicJourney.logMessage("Autorisation de notification accordée")
            } else if let error = error {
                MagicJourney.logMessage("Erreur lors de la demande d'autorisation : \(error)")
            }
        }
    }

    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "app.magicjourney.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 300) // Toutes les 5 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
            logMessage("Rafraîchissement de l'application planifié pour dans 5 minutes")
        } catch {
            logMessage("Impossible de planifier le rafraîchissement de l'application: \(error)")
        }
    }

    private static func handleAppRefresh(task: BGAppRefreshTask) {
        DispatchQueue.global(qos: .background).async {
            logMessage("Début du rafraîchissement des données en arrière-plan")

            let context = PersistenceController.shared.container.viewContext
            let attractionsService = AttractionsService(viewContext: context)

            logMessage("Tentative de fetch et mise à jour des attractions")
            attractionsService.fetchAndUpdateAttractions()
            logMessage("Rafraîchissement des données effectué")
            task.setTaskCompleted(success: true)

            // Replanifier la tâche
            scheduleAppRefresh()
        }
    }

    private static func handleSendAggregatedDataTask(task: BGAppRefreshTask) {
        logMessage("Début de l'envoi des données agrégées en arrière-plan")

        let context = PersistenceController.shared.container.viewContext
        let attractionsService = AttractionsService(viewContext: context)

        logMessage("Envoi des données agrégées")
        attractionsService.sendAggregatedWaitTimesToAPI()
        logMessage("Envoi des données agrégées effectué")
        task.setTaskCompleted(success: true)
        
        // Replanifier la tâche
        scheduleSendAggregatedDataTask()
    }

    private static func scheduleSendAggregatedDataTask() {
        let request = BGAppRefreshTaskRequest(identifier: "app.magicjourney.sendAggregatedData")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // Exécuter toutes les heures

        do {
            try BGTaskScheduler.shared.submit(request)
            logMessage("Envoi des données agrégées planifié pour dans 1 heure")
        } catch {
            logMessage("Impossible de planifier l'envoi des données agrégées: \(error)")
        }
    }

    private static func logMessage(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
}
