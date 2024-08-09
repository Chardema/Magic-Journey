import SwiftUI

struct MainScreen: View {
    @StateObject var attractionsViewModel = AttractionsViewModel(context: PersistenceController.shared.container.viewContext)
    var body: some View {
        TabView {
            HomeScreen(viewContext: PersistenceController.shared.container.viewContext)
                            .environmentObject(attractionsViewModel)
                            .tabItem {
                                Image(systemName: "house.fill")
                                Text("Accueil")
                            }
            
            HoursView()
                
                .tabItem {
                    Image (systemName: "clock.fill")
                    Text ("Horaires")
                }
            
            AttractionsView()
                .environmentObject(attractionsViewModel)
                .tabItem {
                    Image (systemName: "star.fill")
                    Text ("Attractions")
                }
            
            ShowsView()
                .tabItem {
                    Image (systemName: "theatermasks.fill")
                    Text ("Spectacle")
                }
        }
    }
}

struct HomeScreen_Previews: PreviewProvider {
    static var previews: some View {
        MainScreen()
    }
}
