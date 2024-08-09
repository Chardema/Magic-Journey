import SwiftUI
import CoreData

struct HomeScreen: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var fetchedResultsController: AttractionsFetchedResultsController
    @EnvironmentObject var viewModel: AttractionsViewModel
    @Environment(\.scenePhase) var scenePhase
    @State private var showingFilterOptions = false
    @State private var filterButtonPosition: CGRect = .zero

    init(viewContext: NSManagedObjectContext) {
        _fetchedResultsController = StateObject(wrappedValue: AttractionsFetchedResultsController(viewContext: viewContext))
    }

    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    HStack {
                        Text("Accueil")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        Button(action: {
                            withAnimation {
                                showingFilterOptions.toggle()
                            }
                        }) {
                            Image(systemName: "line.horizontal.3.decrease.circle")
                                .imageScale(.large)
                                .background(GeometryReader { geometry in
                                    Color.clear.onAppear {
                                        filterButtonPosition = geometry.frame(in: .global)
                                    }
                                })
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)

                    if fetchedResultsController.fetchedObjects.isEmpty {
                        VStack(spacing: 10) {
                            Text("Vous n'avez pas encore de favoris.")
                                .padding()
                                .foregroundColor(.gray)

                            Button(action: {
                                // Action pour refaire le quiz
                            }) {
                                Text("REFAIRE LE QUIZ")
                                    .font(.headline)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        List {
                            Section {
                                ForEach(fetchedResultsController.fetchedObjects, id: \.self) { attraction in
                                    AttractionsCard(attraction: attraction, deleteAction: {
                                        delete(attraction)
                                    }, circleColor: circleColor)
                                        .transition(.opacity)
                                }
                                .onDelete(perform: deleteAttractions)
                                .listRowBackground(Color(UIColor.systemGroupedBackground))
                            }
                        }
                        .listStyle(.plain)
                        .background(Color.clear)
                    }

                    Spacer()
                }
                .background(Color(UIColor.systemGroupedBackground).opacity(0.7))
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        viewModel.refreshData()
                    }
                }

                if showingFilterOptions {
                    VStack {
                        Spacer().frame(height: filterButtonPosition.maxY)
                        FilterOptionsView()
                            .frame(width: 200)
                            .transition(.opacity.combined(with: .offset(x: 0, y: 10)))
                            .zIndex(1)
                            .clipped()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }
        .onAppear {
            do {
                try fetchedResultsController.fetchedResultsController.performFetch()
            } catch {
                print("Error fetching attractions: \(error)")
            }
        }
    }

    private func delete(_ attraction: Attraction) {
        withAnimation {
            viewContext.delete(attraction)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting attraction: \(error)")
            }
        }
    }

    private func deleteAttractions(offsets: IndexSet) {
        withAnimation {
            offsets.map { fetchedResultsController.fetchedObjects[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting attraction: \(error)")
            }
        }
    }

    func circleColor(for waitTime: Int) -> Color {
        if waitTime > 45 {
            return Color.red.opacity(0.8)
        } else if waitTime >= 30 {
            return Color.orange.opacity(0.8)
        } else {
            return Color.green.opacity(0.8)
        }
    }
}

struct FilterOptionsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                // Action pour le filtre Tous
            }) {
                HStack {
                    Image(systemName: "square.grid.2x2")
                    Text("Tous")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)

            Button(action: {
                // Action pour le filtre Attractions
            }) {
                HStack {
                    Image(systemName: "person.3.fill")
                    Text("Attractions")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)

            Button(action: {
                // Action pour le filtre Spectacles
            }) {
                HStack {
                    Image(systemName: "film")
                    Text("Spectacles")
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(10)
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
        .cornerRadius(10)
        .frame(maxWidth: 200)
    }
}

struct AttractionsCard: View {
    var attraction: Attraction
    var deleteAction: () -> Void
    var circleColor: (Int) -> Color

    var body: some View {
        HStack {
            if let imageName = attraction.name,
               let uiImage = UIImage(named: imageName.normalizedImageName()) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.gray.opacity(0.5), lineWidth: 1))
            } else {
                VStack {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("Pas d'image disponible")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(width: 80, height: 80)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(attraction.name ?? "Unknown")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(attraction.land ?? "Unknown")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if attraction.waitTime > 0 {
                    HStack {
                        Circle()
                            .fill(circleColor(Int(attraction.waitTime)))
                            .frame(width: 30, height: 30)
                        Text("\(attraction.waitTime) min")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 5)
                }
            }
            .padding(.leading, 10)

            Spacer()

            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .padding(.trailing, 10)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attraction.name ?? "Attraction sans nom")
    }
}

#Preview {
    HomeScreen(viewContext: NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType))
}
