import SwiftUI
import CoreData

class AttractionsFetchedResultsController:NSObject, ObservableObject {
    @Published var fetchedObjects: [Attraction] = []
    private(set) var fetchedResultsController: NSFetchedResultsController<Attraction>

    init(viewContext: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Attraction> = Attraction.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isFavorite == true")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Attraction.name, ascending: true)] // Ajoutez un descripteur de tri ici
        // Ajoute ici les descripteurs de tri si nécessaire

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        super.init()
        fetchedResultsController.delegate = self
        
        do {
            try fetchedResultsController.performFetch()
            fetchedObjects = fetchedResultsController.fetchedObjects ?? []
        } catch {
            print("Error fetching attractions: \(error)")
        }
    }
}

extension AttractionsFetchedResultsController: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let attractions = controller.fetchedObjects as? [Attraction] {
            DispatchQueue.main.async {
                self.fetchedObjects = attractions
            }
        }
    }
}
