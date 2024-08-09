import Foundation
import Combine
import CoreData
import UserNotifications

class AttractionsService: ObservableObject {
    @Published var attractions: [Attractionss] = []
    private let viewContext: NSManagedObjectContext
    var cancellable: AnyCancellable?

    private var aggregatedWaitTimes: [String: [String: (sum: Int, count: Int)]] = [:]
    private let aggregationInterval: TimeInterval = 3600 // 1 heure
    private let lastSentDateKey = "lastSentDateKey"

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    func fetchAndUpdateAttractions() {
        guard let url = URL(string: "https://eurojourney.azurewebsites.net/api/attractions") else {
            print("Invalid URL")
            return
        }

        print("Fetching attractions from API...")

        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                print("HTTP response status code: \(httpResponse.statusCode)")
                guard 200..<300 ~= httpResponse.statusCode else {
                    throw URLError(.badServerResponse)
                }
                print("Received data of length: \(data.count)")
                return data
            }
            .decode(type: [Attractionss].self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    print("Successfully fetched data")
                case .failure(let error):
                    print("Error fetching data: \(error)")
                }
            }, receiveValue: { attractionsData in
                self.updateCoreDataWithAttractions(attractionsData)
                self.monitorWaitTimes(newAttractionsData: attractionsData)
                self.attractions = attractionsData

                // Vérifier si l'envoi est nécessaire
                if self.shouldSendAggregatedData() {
                    self.sendAggregatedWaitTimesToAPI()
                }
            })
    }

    private func shouldSendAggregatedData() -> Bool {
        // Récupérer la dernière date d'envoi
        let lastSentDate = UserDefaults.standard.object(forKey: lastSentDateKey) as? Date

        // Si aucune date n'est enregistrée ou si plus de 24 heures se sont écoulées, renvoyer true
        if let lastSentDate = lastSentDate {
            let interval = Date().timeIntervalSince(lastSentDate)
            if interval >= 86400 { // 86400 secondes dans une journée
                return true
            } else {
                print("L'envoi des données a déjà été effectué aujourd'hui.")
                return false
            }
        } else {
            // Si c'est la première fois
            return true
        }
    }

    public func sendAggregatedWaitTimesToAPI() {
        // Charger les données agrégées depuis le stockage local
        loadAggregatedWaitTimesLocally()

        let aggregatedAverages = calculateHourlyAverages()
        
        print("Données agrégées avant envoi à l'API : \(aggregatedAverages)")

        // Construire la requête API
        guard let url = URL(string: "https://eurojourney.azurewebsites.net/api/wait-times") else {
            print("URL invalide")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            // Convertir les données agrégées en JSON
            let jsonData = try JSONEncoder().encode(aggregatedAverages)
            request.httpBody = jsonData
        } catch {
            print("Erreur lors de l'encodage JSON : \(error)")
            return
        }

        // Envoyer la requête
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("Erreur lors de l'envoi des données : \(error)")
            } else {
                print("Données agrégées envoyées avec succès à l'API")
                self.clearAggregatedWaitTimesInCoreData() // Supprimer les données après l'envoi
                self.aggregatedWaitTimes = [:]
                self.saveAggregatedWaitTimesLocally() // Sauvegarder l'état vide

                // Enregistrer la date actuelle comme dernière date d'envoi
                UserDefaults.standard.set(Date(), forKey: self.lastSentDateKey)
            }
        }.resume()
    }


    private func updateCoreDataWithAttractions(_ attractionsData: [Attractionss]) {
        print("Updating Core Data with \(attractionsData.count) attractions")

        let fetchRequest: NSFetchRequest<Attraction> = Attraction.fetchRequest()
        let ids = attractionsData.map { $0.id }
        fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

        do {
            let existingAttractions = try viewContext.fetch(fetchRequest)
            let existingAttractionsMap = Dictionary(uniqueKeysWithValues: existingAttractions.map { ($0.id, $0) })

            for attractionData in attractionsData {
                if let existingAttraction = existingAttractionsMap[attractionData.id] {
                    existingAttraction.waitTime = Int16(attractionData.waitTime ?? 0)
                    existingAttraction.status = attractionData.status
                    existingAttraction.lastKnownWaitTime = Int16(attractionData.waitTime ?? 0)
                } else {
                    print("Creating new attraction: \(attractionData.name)")
                    let newAttraction = Attraction(context: viewContext)
                    newAttraction.id = attractionData.id
                    newAttraction.name = attractionData.name
                    newAttraction.waitTime = Int16(attractionData.waitTime ?? 0)
                    newAttraction.status = attractionData.status
                    newAttraction.land = attractionData.land
                    newAttraction.descriptionText = attractionData.description
                    newAttraction.lastKnownWaitTime = Int16(attractionData.waitTime ?? 0)
                }

                // Agrégation des temps d'attente par heure
                let attractionId = attractionData.id
                let currentHour = Calendar.current.component(.hour, from: Date())
                let hourKey = String(format: "%02d", currentHour)

                // Vérifier si l'attraction et l'heure existent déjà dans Core Data
                let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "attractionId == %@ AND hour == %@", attractionId.uuidString, hourKey)
                do {
                    let existingData = try viewContext.fetch(fetchRequest)

                    if let aggregatedWaitTime = existingData.first {
                        // Mettre à jour les données existantes
                        aggregatedWaitTime.sumWaitTime += Int32(attractionData.waitTime ?? 0)
                        aggregatedWaitTime.countWaitTime += 1
                    } else {
                        // Créer un nouvel enregistrement
                        let aggregatedWaitTime = AggregatedWaitTime(context: viewContext)
                        aggregatedWaitTime.attractionId = attractionId.uuidString
                        aggregatedWaitTime.hour = hourKey
                        aggregatedWaitTime.sumWaitTime = Int32(attractionData.waitTime ?? 0)
                        aggregatedWaitTime.countWaitTime = 1
                    }
                } catch {
                    print("Erreur lors de la récupération/mise à jour des données agrégées : \(error)")
                }
            }

            try viewContext.save()
            print("Core Data saved successfully")
        } catch {
            print("Error updating Core Data: \(error)")
        }
    }


    private func monitorWaitTimes(newAttractionsData: [Attractionss]) {
        let fetchRequest: NSFetchRequest<Attraction> = Attraction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isFavorite == true")

        do {
            let favoriteAttractions = try viewContext.fetch(fetchRequest)

            for attraction in favoriteAttractions {
                if let newAttractionData = newAttractionsData.first(where: { $0.id == attraction.id }) {
                    let newWaitTime = newAttractionData.waitTime ?? 0
                    if newWaitTime != Int(attraction.lastKnownWaitTime) {
                        sendNotification(for: attraction, newWaitTime: newWaitTime)
                        attraction.lastKnownWaitTime = Int16(newWaitTime)
                        try? viewContext.save()
                    }
                }
            }
        } catch {
            print("Error fetching attractions: \(error)")
        }
    }

    func sendNotification(for attraction: Attraction, newWaitTime: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(attraction.name ?? "Attraction") : Changement de temps d'attente"
        content.body = "Le temps d'attente est maintenant de \(newWaitTime) minutes."

        // Créer un déclencheur pour envoyer la notification immédiatement
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        // Créer la requête de notification
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        // Ajouter la requête au centre de notifications
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Erreur lors de l'ajout de la notification : \(error)")
            }
        }
    }

    private func calculateHourlyAverages() -> [String: [String: Int]] {
        var averages: [String: [String: Int]] = [:]

        // Définir les tranches horaires pour matin, midi et soir
        let morningHours = 9..<12  // Exemple : de 9h à 11h
        let afternoonHours = 12..<17 // Exemple : de 12h à 16h
        let eveningHours = 17..<23 // Exemple : de 17h à 22h

        // Parcourir les données agrégées
        for (attractionId, hourData) in aggregatedWaitTimes {
            var attractionAverages: [String: Int] = [:]

            for (hourKey, (sum, count)) in hourData {
                let hour = Int(hourKey)!
                let average = count > 0 ? sum / count : 0

                // Regrouper les moyennes par tranche horaire
                if morningHours.contains(hour) {
                    attractionAverages["matin"] = (attractionAverages["matin"] ?? 0) + average
                } else if afternoonHours.contains(hour) {
                    attractionAverages["midi"] = (attractionAverages["midi"] ?? 0) + average
                } else if eveningHours.contains(hour) {
                    attractionAverages["soir"] = (attractionAverages["soir"] ?? 0) + average
                }
            }

            // Calculer les moyennes finales pour chaque tranche horaire
            for period in ["matin", "midi", "soir"] {
                if let total = attractionAverages[period], total > 0 {
                    let count = hourData.filter {
                        let hour = Int($0.key)!
                        switch period {
                        case "matin": return morningHours.contains(hour)
                        case "midi": return afternoonHours.contains(hour)
                        case "soir": return eveningHours.contains(hour)
                        default: return false
                        }
                    }.count

                    attractionAverages[period] = total / count
                } else {
                    attractionAverages[period] = 0
                }
            }

            averages[attractionId] = attractionAverages
        }

        return averages
    }

    private func clearAggregatedWaitTimesInCoreData() {
        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        do {
            let aggregatedWaitTimeData = try viewContext.fetch(fetchRequest)
            for data in aggregatedWaitTimeData {
                viewContext.delete(data)
            }
            try viewContext.save()
        } catch {
            print("Erreur lors de la suppression des données agrégées : \(error)")
        }
    }

    private func isParkClosed() -> Bool {
        // Implémentez votre logique pour déterminer si le parc est fermé
        // Par exemple, vous pouvez vérifier l'heure actuelle ou le statut des attractions
        // ...

        // Exemple simple basé sur l'heure (à adapter selon vos besoins)
        let currentHour = Calendar.current.component(.hour, from: Date())
        return currentHour < 9 || currentHour >= 23
    }

    private func loadAggregatedWaitTimesLocally() {
        // Charger les données agrégées depuis Core Data
        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        do {
            let aggregatedWaitTimeData = try viewContext.fetch(fetchRequest)
            for data in aggregatedWaitTimeData {
                if aggregatedWaitTimes[data.attractionId!] == nil {
                    aggregatedWaitTimes[data.attractionId!] = [:]
                }
                aggregatedWaitTimes[data.attractionId!]![data.hour!] = (Int(data.sumWaitTime), Int(data.countWaitTime))
            }
        } catch {
            print("Erreur lors du chargement des données agrégées : \(error)")
        }
    }

    private func saveAggregatedWaitTimesLocally() {
        // Supprimer les anciennes données agrégées
        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        do {
            let existingData = try viewContext.fetch(fetchRequest)
            for object in existingData {
                viewContext.delete(object)
            }
        } catch {
            print("Erreur lors de la suppression des anciennes données agrégées : \(error)")
        }

        // Sauvegarder les nouvelles données agrégées
        for (attractionId, hourData) in aggregatedWaitTimes {
            for (hourKey, (sum, count)) in hourData {
                let aggregatedWaitTime = AggregatedWaitTime(context: viewContext)
                aggregatedWaitTime.attractionId = attractionId
                aggregatedWaitTime.hour = hourKey
                aggregatedWaitTime.sumWaitTime = Int32(sum)
                aggregatedWaitTime.countWaitTime = Int32(count)
            }
        }

        do {
            try viewContext.save()
        } catch {
            print("Erreur lors de la sauvegarde des données agrégées : \(error)")
        }
    }

    deinit {
        cancellable?.cancel()
    }
}
