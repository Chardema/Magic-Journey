import Foundation
import CoreData
import SwiftUI
import Combine

class AttractionsViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    @Published private(set) var attractions: [Attraction] = []

    private let attractionsService: AttractionsService
    private let fetchedResultsController: NSFetchedResultsController<Attraction>
    private var subscriptions = Set<AnyCancellable>() // Pour gérer les abonnements Combine

    init(context: NSManagedObjectContext) {
        self.attractionsService = AttractionsService(viewContext: context)
        let fetchRequest: NSFetchRequest<Attraction> = Attraction.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Attraction.name, ascending: true)]

        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        super.init()
        fetchedResultsController.delegate = self

        // Publisher pour mettre à jour attractions lorsque les données changent
        fetchedResultsController.publisher(for: \.fetchedObjects)
            .map { $0 as? [Attraction] ?? [] } // Conversion en [Attraction]
            .receive(on: DispatchQueue.main) // Assurez-vous que la mise à jour se fait sur le thread principal
            .sink { [weak self] newAttractions in
                self?.attractions = newAttractions
            }
            .store(in: &subscriptions) // Stockez l'abonnement dans subscriptions
        
        // Récupération initiale des données lors de l'initialisation
        do {
            try fetchedResultsController.performFetch()
            attractions = fetchedResultsController.fetchedObjects ?? []
        } catch {
            print("Error performing fetch: \(error)")
        }
    }

    func refreshData() {
        attractionsService.fetchAndUpdateAttractions()
    }

    // MARK: - NSFetchedResultsControllerDelegate

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let newAttractions = controller.fetchedObjects as? [Attraction] else { return }
        attractions = newAttractions
    }
}
