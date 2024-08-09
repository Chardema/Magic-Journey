import SwiftUI
import CoreData
import BackgroundTasks

struct AttractionsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Attraction.waitTime, ascending: true)]) var attractions: FetchedResults<Attraction>

    @State private var showingFilterOptions = false
    @StateObject private var persistenceController = PersistenceController.shared

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 20)], spacing: 20) {
                    ForEach(attractions) { attraction in
                        AttractionCard(attraction: attraction, deleteAction: {
                            delete(attraction)
                        }, circleColor: circleColor)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
        .onAppear {
            let attractionsService = AttractionsService(viewContext: persistenceController.container.viewContext)
            attractionsService.fetchAndUpdateAttractions() // Charger les données initialement
            scheduleAppRefresh()
        }
    }

    func scheduleAppRefresh() {
        let request = BGProcessingTaskRequest(identifier: "app.magicjourney.refresh")
        request.requiresNetworkConnectivity = true // Nécessaire pour accéder à l'API
        request.requiresExternalPower = false // Peut s'exécuter même sur batterie

        do {
            try BGTaskScheduler.shared.submit(request)
            print("App refresh scheduled successfully")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    func delete(_ attraction: Attraction) {
        withAnimation {
            viewContext.delete(attraction)
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

struct AttractionCard: View {
    @ObservedObject var attraction: Attraction
    var deleteAction: () -> Void
    var circleColor: (Int) -> Color

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading) {
                AttractionImage(imageName: attraction.name?.normalizedImageName())
                
                Text(attraction.name ?? "Erreur")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.top, 5)
                
                Text(attraction.land ?? "Erreur")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                FavoriteButton(attraction: attraction)

                DetailButton()
            }
            .padding()
            .background(Color.white)
            .cornerRadius(15)
            .shadow(radius: 5)
            
            AttractionStatusView(attraction: attraction, circleColor: circleColor)
        }
    }
}

struct AttractionImage: View {
    let imageName: String?

    var body: some View {
        Group {
            if let imageName = imageName, let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 80)
                    .clipped()
                    .cornerRadius(15)
            } else {
                Image("defaultImageName")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 80)
                    .clipped()
                    .cornerRadius(15)
            }
        }
    }
}

struct FavoriteButton: View {
    @ObservedObject var attraction: Attraction

    var body: some View {
        Button(action: {
            attraction.isFavorite.toggle()
            try? attraction.managedObjectContext?.save()
        }) {
            Text("Favori")
                .font(.subheadline)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .background(attraction.isFavorite ? Color.red : Color.clear)
                .foregroundColor(attraction.isFavorite ? .white : .red)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red, lineWidth: 1)
                )
        }
    }
}

struct DetailButton: View {
    var body: some View {
        Button(action: {
            // Action pour le bouton détails
        }) {
            Text("Détails")
                .font(.subheadline)
                .foregroundColor(.blue)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue, lineWidth: 1)
                )
        }
    }
}

struct AttractionStatusView: View {
    @ObservedObject var attraction: Attraction
    var circleColor: (Int) -> Color

    var body: some View {
        Group {
            if attraction.status == "DOWN" {
                StatusText(text: "Indispo")
            } else if attraction.status == "CLOSED" {
                StatusText(text: "Fermée")
            } else if attraction.waitTime > 0 { // Vérifier si le temps d'attente est supérieur à 0
                WaitTimeCircle(waitTime: Int(attraction.waitTime), circleColor: circleColor)
            } else { // Cas où le temps d'attente est 0
                StatusText(text: "Sans fil")
            }
        }
        .padding([.top, .trailing], 8)
    }}

struct StatusText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(5)
            .background(Color.gray.opacity(0.8))
            .cornerRadius(5)
    }
}

struct WaitTimeCircle: View {
    let waitTime: Int
    var circleColor: (Int) -> Color

    var body: some View {
        ZStack {
            Circle()
                .fill(circleColor(waitTime))
                .frame(width: 50, height: 50)
            Text("\(waitTime)")
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    AttractionsView()
}
