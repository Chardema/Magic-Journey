import Foundation
import Combine
import CoreData
import UserNotifications

class AttractionsService: ObservableObject {
    @Published var attractions: [Attractionss] = []
    private let viewContext: NSManagedObjectContext
    private var cancellable: AnyCancellable?

    private var aggregatedWaitTimes: [String: [String: (sum: Int, count: Int)]] = [:]
    private let aggregationInterval: TimeInterval = 3600 // 1 heure
    private let lastSentDateKey = "lastSentDateKey"

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        loadAggregatedWaitTimesLocally() // Charger les données agrégées dès l'initialisation
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
        let lastSentDate = UserDefaults.standard.object(forKey: lastSentDateKey) as? Date
        let now = Date()

        // Si aucune date n'est enregistrée ou si plus de 24 heures se sont écoulées
        guard let lastSentDate = lastSentDate else {
            return true
        }

        let interval = now.timeIntervalSince(lastSentDate)
        if interval >= 86400 { // 86400 secondes = 1 jour
            return true
        } else {
            print("Data has already been sent today.")
            return false
        }
    }

    public func sendAggregatedWaitTimesToAPI() {
        loadAggregatedWaitTimesLocally()

        let aggregatedAverages = calculateHourlyAverages()
        
        print("Aggregated data before sending to API: \(aggregatedAverages)")

        guard let url = URL(string: "https://eurojourney.azurewebsites.net/api/wait-times") else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONEncoder().encode(aggregatedAverages)
            request.httpBody = jsonData
        } catch {
            print("Error encoding JSON: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("Error sending data: \(error)")
            } else {
                print("Aggregated data sent successfully to the API")
                self.clearAggregatedWaitTimesInCoreData()
                self.aggregatedWaitTimes = [:]
                self.saveAggregatedWaitTimesLocally()
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
                let attraction = existingAttractionsMap[attractionData.id] ?? Attraction(context: viewContext)
                attraction.id = attractionData.id
                attraction.name = attractionData.name
                attraction.waitTime = Int16(attractionData.waitTime ?? 0)
                attraction.status = attractionData.status
                attraction.land = attractionData.land
                attraction.descriptionText = attractionData.description
                attraction.lastKnownWaitTime = Int16(attractionData.waitTime ?? 0)

                aggregateWaitTimes(for: attractionData)
            }

            try viewContext.save()
            print("Core Data saved successfully")
        } catch {
            print("Error updating Core Data: \(error)")
        }
    }

    private func aggregateWaitTimes(for attractionData: Attractionss) {
        let attractionId = attractionData.id
        let currentHour = Calendar.current.component(.hour, from: Date())
        let hourKey = String(format: "%02d", currentHour)

        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "attractionId == %@ AND hour == %@", attractionId.uuidString, hourKey)

        do {
            let existingData = try viewContext.fetch(fetchRequest).first

            if let aggregatedWaitTime = existingData {
                aggregatedWaitTime.sumWaitTime += Int32(attractionData.waitTime ?? 0)
                aggregatedWaitTime.countWaitTime += 1
            } else {
                let newAggregatedWaitTime = AggregatedWaitTime(context: viewContext)
                newAggregatedWaitTime.attractionId = attractionId.uuidString
                newAggregatedWaitTime.hour = hourKey
                newAggregatedWaitTime.sumWaitTime = Int32(attractionData.waitTime ?? 0)
                newAggregatedWaitTime.countWaitTime = 1
            }
        } catch {
            print("Error aggregating wait times: \(error)")
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

    private func sendNotification(for attraction: Attraction, newWaitTime: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(attraction.name ?? "Attraction") : Changement de temps d'attente"
        content.body = "Le temps d'attente est maintenant de \(newWaitTime) minutes."

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error adding notification: \(error)")
            }
        }
    }

    private func calculateHourlyAverages() -> [String: [String: Int]] {
        var averages: [String: [String: Int]] = [:]

        let morningHours = 9..<12
        let afternoonHours = 12..<17
        let eveningHours = 17..<23

        for (attractionId, hourData) in aggregatedWaitTimes {
            var attractionAverages: [String: Int] = [:]

            for (hourKey, (sum, count)) in hourData {
                let hour = Int(hourKey)!
                let average = count > 0 ? sum / count : 0

                if morningHours.contains(hour) {
                    attractionAverages["matin"] = (attractionAverages["matin"] ?? 0) + average
                } else if afternoonHours.contains(hour) {
                    attractionAverages["midi"] = (attractionAverages["midi"] ?? 0) + average
                } else if eveningHours.contains(hour) {
                    attractionAverages["soir"] = (attractionAverages["soir"] ?? 0) + average
                }
            }

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
            print("Error clearing aggregated data: \(error)")
        }
    }

    private func loadAggregatedWaitTimesLocally() {
        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        do {
            let aggregatedWaitTimeData = try viewContext.fetch(fetchRequest)
            for data in aggregatedWaitTimeData {
                aggregatedWaitTimes[data.attractionId!] = [:]
                aggregatedWaitTimes[data.attractionId!]![data.hour!] = (Int(data.sumWaitTime), Int(data.countWaitTime))
            }
        } catch {
            print("Error loading aggregated data: \(error)")
        }
    }

    private func saveAggregatedWaitTimesLocally() {
        let fetchRequest: NSFetchRequest<AggregatedWaitTime> = AggregatedWaitTime.fetchRequest()
        do {
            let existingData = try viewContext.fetch(fetchRequest)
            for object in existingData {
                viewContext.delete(object)
            }
        } catch {
            print("Error clearing old aggregated data: \(error)")
        }

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
            print("Error saving aggregated data: \(error)")
        }
    }

    deinit {
        cancellable?.cancel()
    }
}
