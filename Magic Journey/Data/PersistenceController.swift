import CoreData

class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    @Published var savedAttractions: [Attraction] = []

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AttractionsModel")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // TODO: Remplacer par une gestion d'erreur appropriée
                print("Error loading Core Data: \(error), \(error.userInfo)")
            } else {
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Initial fetch to populate savedAttractions
        fetchSavedAttractions()
    }

    static func sharedContainer() -> NSPersistentContainer {
        return PersistenceController.shared.container
    }

    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Context saved successfully.")
                // Update the savedAttractions array after saving
                fetchSavedAttractions()
            } catch {
                // TODO: Remplacer par une gestion d'erreur appropriée
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        } else {
            print("No changes in context to save.")
        }
    }
    
    func fetchSavedAttractions() {
        let request = NSFetchRequest<Attraction>(entityName: "Attraction")
        do {
            savedAttractions = try container.viewContext.fetch(request)
            print("Fetched saved attractions: \(savedAttractions)")
        } catch let error {
            print("Error fetching saved attractions: \(error)")
        }
    }
}
