import Foundation

// Extension pour ajouter la méthode normalizedImageName à String
extension String {
    func normalizedImageName() -> String {
        let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789éè") // Inclure é et è
        
        // Utiliser folding pour normaliser les caractères accentués
        return self.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .filter { allowedCharacters.contains($0) }
    }
}

