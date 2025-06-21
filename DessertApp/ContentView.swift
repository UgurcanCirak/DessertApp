import SwiftUI
import UserNotifications

// MARK: - Favorites Manager (Singleton)
class FavoritesManager: ObservableObject {
    static let shared = FavoritesManager()
    @Published var favorites: Set<String> = []
    
    private let userDefaults = UserDefaults.standard
    private let favoritesKey = "FavoriteDesserts"
    
    private init() {
        loadFavorites()
    }
    
    func toggleFavorite(_ dessertName: String) {
        if favorites.contains(dessertName) {
            favorites.remove(dessertName)
            AchievementManager.shared.trackFavoriteRemoved()
        } else {
            favorites.insert(dessertName)
            AchievementManager.shared.trackFavoriteAdded()
        }
        saveFavorites()
    }
    
    func isFavorite(_ dessertName: String) -> Bool {
        return favorites.contains(dessertName)
    }
    
    private func saveFavorites() {
        let favoritesArray = Array(favorites)
        userDefaults.set(favoritesArray, forKey: favoritesKey)
    }
    
    private func loadFavorites() {
        if let savedFavorites = userDefaults.array(forKey: favoritesKey) as? [String] {
            favorites = Set(savedFavorites)
            // Achievement manager için mevcut favori sayısını güncelle
            AchievementManager.shared.userStats.favoritesCount = favorites.count
        }
    }
}

// MARK: - Timer Manager
class TimerManager: ObservableObject {
    @Published var isActive = false
    @Published var timeRemaining = 0
    @Published var totalTime = 0
    
    private var timer: Timer?
    
    func startTimer(minutes: Int) {
        stopTimer()
        totalTime = minutes * 60
        timeRemaining = totalTime
        isActive = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stopTimer()
                // Timer bitti bildirimi burada gösterilebilir
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        isActive = false
        timeRemaining = 0
        totalTime = 0
    }
    
    func pauseTimer() {
        timer?.invalidate()
        timer = nil
        isActive = false
    }
    
    func resumeTimer() {
        guard timeRemaining > 0 else { return }
        isActive = true
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.stopTimer()
            }
        }
    }
    
    var progress: Double {
        guard totalTime > 0 else { return 0 }
        return Double(totalTime - timeRemaining) / Double(totalTime)
    }
    
    var formattedTime: String {
        let minutes = timeRemaining / 60
        let seconds = timeRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
// MARK: - Achievement Model
struct Achievement: Identifiable, Codable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let targetValue: Int
    let type: AchievementType
    var isUnlocked: Bool = false
    var unlockedDate: Date?
    var progress: Int = 0
    
    var progressPercentage: Double {
        return min(Double(progress) / Double(targetValue), 1.0)
    }
    
    var isCompleted: Bool {
        return progress >= targetValue
    }
}

enum AchievementType: String, Codable, CaseIterable {
    case firstDessert = "first_dessert"
    case countryExplorer = "country_explorer"
    case timeKeeper = "time_keeper"
    case recipeCollector = "recipe_collector"
    case calorieTracker = "calorie_tracker"
    case favoriteCollector = "favorite_collector"
    case weeklyChef = "weekly_chef"
    case dessertMaster = "dessert_master"
}

// MARK: - User Stats Model
struct UserStats: Codable {
    var viewedCountries: Set<String> = []
    var viewedDesserts: Set<String> = []
    var timerUsages: Int = 0
    var calorieCalculations: Int = 0
    var favoritesCount: Int = 0
    var dailyActivities: [String] = [] // Date strings in "yyyy-MM-dd" format
    var totalRecipesViewed: Int = 0
    
    mutating func addViewedCountry(_ country: String) {
        viewedCountries.insert(country)
    }
    
    mutating func addViewedDessert(_ dessert: String) {
        viewedDesserts.insert(dessert)
        totalRecipesViewed += 1
    }
    
    mutating func updateDailyActivity() {
        let today = DateFormatter.dayFormatter.string(from: Date())
        if !dailyActivities.contains(today) {
            dailyActivities.append(today)
        }
    }
    
    func getConsecutiveDays() -> Int {
        let sortedDates = dailyActivities.compactMap { DateFormatter.dayFormatter.date(from: $0) }.sorted()
        guard !sortedDates.isEmpty else { return 0 }
        
        var consecutive = 1
        var current = sortedDates.last!
        
        for i in stride(from: sortedDates.count - 2, through: 0, by: -1) {
            let previousDate = sortedDates[i]
            let daysDifference = Calendar.current.dateComponents([.day], from: previousDate, to: current).day ?? 0
            
            if daysDifference == 1 {
                consecutive += 1
                current = previousDate
            } else {
                break
            }
        }
        
        return consecutive
    }
}

extension DateFormatter {
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let achievementFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}
// MARK: - Achievement Manager
class AchievementManager: ObservableObject {
    static let shared = AchievementManager()
    
    @Published var achievements: [Achievement] = []
    @Published var unlockedAchievements: [Achievement] = []
    @Published var showingAchievement: Achievement?
    
    private let userDefaults = UserDefaults.standard
    private let achievementsKey = "UserAchievements"
    private let statsKey = "UserStats"
    
    // Kullanıcı istatistikleri
    @Published var userStats = UserStats()
    
    private init() {
        setupInitialAchievements()
        loadAchievements()
        loadUserStats()
        requestNotificationPermission()
    }
    
    private func setupInitialAchievements() {
        achievements = [
            Achievement(
                title: "İlk Tatlım",
                description: "İlk tatlı tarifini görüntüledin!",
                icon: "star.fill",
                targetValue: 1,
                type: .firstDessert
            ),
            Achievement(
                title: "Dünya Gezgini",
                description: "5 farklı ülkenin tatlısını keşfet",
                icon: "globe",
                targetValue: 5,
                type: .countryExplorer
            ),
            Achievement(
                title: "Zamanlayıcı Ustası",
                description: "10 kez timer kullan",
                icon: "timer",
                targetValue: 10,
                type: .timeKeeper
            ),
            Achievement(
                title: "Tarif Koleksiyoncusu",
                description: "20 farklı tarif gör",
                icon: "book.fill",
                targetValue: 20,
                type: .recipeCollector
            ),
            Achievement(
                title: "Kalori Takipçisi",
                description: "Kalori hesaplayıcısını 15 kez kullan",
                icon: "flame.fill",
                targetValue: 15,
                type: .calorieTracker
            ),
            Achievement(
                title: "Favori Avcısı",
                description: "10 tarifi favorilerine ekle",
                icon: "heart.fill",
                targetValue: 10,
                type: .favoriteCollector
            ),
            Achievement(
                title: "Haftalık Şef",
                description: "7 gün üst üste uygulama kullan",
                icon: "calendar",
                targetValue: 7,
                type: .weeklyChef
            ),
            Achievement(
                title: "Tatlı Ustası",
                description: "Tüm ülkelerin tatlılarını keşfet",
                icon: "crown.fill",
                targetValue: 12, // Toplam ülke sayısı
                type: .dessertMaster
            )
        ]
    }
    
    // MARK: - Progress Tracking
    func trackDessertView(_ dessertName: String, country: String) {
        updateProgress(.firstDessert, increment: 1)
        updateProgress(.recipeCollector, increment: 1)
        
        // Ülke takibi
        userStats.addViewedCountry(country)
        updateProgress(.countryExplorer, increment: 0) // Manuel güncelleme
        updateProgress(.dessertMaster, increment: 0) // Manuel güncelleme
        
        // Günlük aktivite takibi
        userStats.updateDailyActivity()
        checkWeeklyProgress()
        
        saveUserStats()
    }
    
    func trackTimerUsage() {
        updateProgress(.timeKeeper, increment: 1)
        userStats.timerUsages += 1
        saveUserStats()
    }
    
    func trackCalorieCalculation() {
        updateProgress(.calorieTracker, increment: 1)
        userStats.calorieCalculations += 1
        saveUserStats()
    }
    
    func trackFavoriteAdded() {
        userStats.favoritesCount += 1
        updateProgress(.favoriteCollector, increment: 0) // Manuel güncelleme
        saveUserStats()
    }
    
    func trackFavoriteRemoved() {
        userStats.favoritesCount = max(0, userStats.favoritesCount - 1)
        updateProgress(.favoriteCollector, increment: 0) // Manuel güncelleme
        saveUserStats()
    }
    
    private func checkWeeklyProgress() {
        let consecutiveDays = userStats.getConsecutiveDays()
        if let weeklyAchievement = achievements.first(where: { $0.type == .weeklyChef }) {
            let index = achievements.firstIndex(where: { $0.id == weeklyAchievement.id })!
            achievements[index].progress = consecutiveDays
            
            if consecutiveDays >= weeklyAchievement.targetValue && !weeklyAchievement.isUnlocked {
                unlockAchievement(weeklyAchievement)
            }
        }
    }
    
    private func updateProgress(_ type: AchievementType, increment: Int) {
        guard let index = achievements.firstIndex(where: { $0.type == type }) else { return }
        
        let achievement = achievements[index]
        if achievement.isUnlocked { return }
        
        // Özel durumlar için manuel güncelleme
        switch type {
        case .countryExplorer:
            achievements[index].progress = userStats.viewedCountries.count
        case .dessertMaster:
            achievements[index].progress = userStats.viewedCountries.count
        case .favoriteCollector:
            achievements[index].progress = userStats.favoritesCount
        default:
            achievements[index].progress += increment
        }
        
        // Başarım tamamlandı mı kontrol et
        if achievements[index].isCompleted && !achievements[index].isUnlocked {
            unlockAchievement(achievements[index])
        }
        
        saveAchievements()
    }
    
    private func unlockAchievement(_ achievement: Achievement) {
        guard let index = achievements.firstIndex(where: { $0.id == achievement.id }) else { return }
        
        achievements[index].isUnlocked = true
        achievements[index].unlockedDate = Date()
        
        unlockedAchievements.append(achievements[index])
        showingAchievement = achievements[index]
        
        // Bildirim gönder
        sendNotification(for: achievements[index])
        
        saveAchievements()
    }
    
    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                print("Notification permission: \(granted)")
            }
        }
    }
    
    private func sendNotification(for achievement: Achievement) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Başarım Kazanıldı!"
        content.body = "\(achievement.title) - \(achievement.description)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: achievement.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Data Persistence
    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            userDefaults.set(data, forKey: achievementsKey)
        }
    }
    
    private func loadAchievements() {
        if let data = userDefaults.data(forKey: achievementsKey),
           let savedAchievements = try? JSONDecoder().decode([Achievement].self, from: data) {
            // Mevcut başarımlarla birleştir (yeni başarımlar için)
            for savedAchievement in savedAchievements {
                if let index = achievements.firstIndex(where: { $0.type == savedAchievement.type }) {
                    achievements[index] = savedAchievement
                }
            }
            unlockedAchievements = achievements.filter { $0.isUnlocked }
        }
    }
    
    private func saveUserStats() {
        if let data = try? JSONEncoder().encode(userStats) {
            userDefaults.set(data, forKey: statsKey)
        }
    }
    
    private func loadUserStats() {
        if let data = userDefaults.data(forKey: statsKey),
           let savedStats = try? JSONDecoder().decode(UserStats.self, from: data) {
            userStats = savedStats
        }
    }
}
// MARK: - Kalori Hesaplayıcı
class CalorieCalculator {
    // Tatlı türlerine göre ortalama kalori değerleri (100g başına)
    private static let calorieDatabase: [String: Int] = [
        "baklava": 520,
        "künefe": 280,
        "sütlaç": 150,
        "tiramisu": 450,
        "gelato": 200,
        "macaron": 400,
        "mochi": 250,
        "waffle": 300,
        "cheesecake": 350,
        "gulab jamun": 480,
        "churros": 380,
        "brigadeiro": 420,
        "sachertorte": 400,
        "tres leches": 320
    ]
    
    // Ortalama porsiyon ağırlıkları (gram)
    private static let portionWeights: [String: Int] = [
        "baklava": 80,
        "künefe": 150,
        "sütlaç": 120,
        "tiramisu": 100,
        "gelato": 100,
        "macaron": 20,
        "mochi": 50,
        "waffle": 120,
        "cheesecake": 120,
        "gulab jamun": 60,
        "churros": 80,
        "brigadeiro": 25,
        "sachertorte": 100,
        "tres leches": 110
    ]
    
    static func calculateCaloriesPerServing(for dessertName: String) -> Int {
        let normalizedName = dessertName.lowercased()
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ö", with: "o")
        
        // Önce tam eşleşme ara
        if let caloriesPer100g = calorieDatabase[normalizedName],
           let portionWeight = portionWeights[normalizedName] {
            return (caloriesPer100g * portionWeight) / 100
        }
        
        // Kısmi eşleşme ara
        for (key, caloriesPer100g) in calorieDatabase {
            if normalizedName.contains(key) || key.contains(normalizedName) {
                let portionWeight = portionWeights[key] ?? 100
                return (caloriesPer100g * portionWeight) / 100
            }
        }
        
        // Varsayılan değer (ortalama tatlı)
        return 300
    }
    
    static func getPortionWeight(for dessertName: String) -> Int {
        let normalizedName = dessertName.lowercased()
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ö", with: "o")
        
        if let weight = portionWeights[normalizedName] {
            return weight
        }
        
        for (key, weight) in portionWeights {
            if normalizedName.contains(key) || key.contains(normalizedName) {
                return weight
            }
        }
        
        return 100 // Varsayılan 100g
    }
}
// MARK: - Ana Content View
struct ContentView: View {
    @State private var showCountryList = false
    @State private var selectedTab = 0
    @StateObject private var favoritesManager = FavoritesManager.shared
    @StateObject private var achievementManager = AchievementManager.shared
    @State private var showingAchievementPopup = false
    
    var body: some View {
        Group {
            if !showCountryList {
                // Hoş geldin sayfası - Tab bar olmadan
                NavigationView {
                    WelcomeView(showCountryList: $showCountryList)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                // Ana uygulama - Tab bar ile
                TabView(selection: $selectedTab) {
                    NavigationView {
                        CountryListView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "globe")
                        Text("Keşfet")
                    }
                    .tag(0)
                    
                    NavigationView {
                        FavoritesView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "heart.fill")
                        Text("Favoriler")
                    }
                    .tag(1)
                    
                    NavigationView {
                        SearchView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Ara")
                    }
                    .tag(2)
                    
                    NavigationView {
                        AchievementsView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "trophy.fill")
                        Text("Başarımlar")
                    }
                    .tag(3)
                    
                    NavigationView {
                        TimerView()
                    }
                    .navigationViewStyle(StackNavigationViewStyle())
                    .tabItem {
                        Image(systemName: "timer")
                        Text("Zamanlayıcı")
                    }
                    .tag(4)
                }
                .environmentObject(favoritesManager)
                .environmentObject(achievementManager)
            }
        }
        .overlay(
            // Achievement Popup Overlay
            Group {
                if showingAchievementPopup, let achievement = achievementManager.showingAchievement {
                    AchievementPopupView(
                        achievement: achievement,
                        isPresented: $showingAchievementPopup
                    )
                }
            }
        )
        .onReceive(achievementManager.$showingAchievement) { achievement in
            if achievement != nil {
                showingAchievementPopup = true
            }
        }
        .onChange(of: showingAchievementPopup) { isShowing in
            if !isShowing {
                achievementManager.showingAchievement = nil
            }
        }
    }
}

// MARK: - Hoş Geldin Sayfası
struct WelcomeView: View {
    @Binding var showCountryList: Bool
    @State private var animateTitle = false
    @State private var animateSubtitle = false
    @State private var animateButton = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient Background
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.7, blue: 0.8),
                        Color(red: 0.9, green: 0.5, blue: 0.9),
                        Color(red: 0.7, green: 0.8, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 40) {
                    Spacer()
                    
                    // Ana Başlık
                    VStack(spacing: 20) {
                        Text("🍮")
                            .font(.system(size: 80))
                            .scaleEffect(animateTitle ? 1.0 : 0.5)
                            .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateTitle)
                        
                        Text("Sweet World")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                            .opacity(animateTitle ? 1 : 0)
                            .offset(y: animateTitle ? 0 : 30)
                            .animation(.easeOut(duration: 0.8).delay(0.3), value: animateTitle)
                    }
                    
                    // Alt Başlık
                    Text("Dünyanın En Lezzetli Tatlılarını Keşfedin")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .opacity(animateSubtitle ? 1 : 0)
                        .offset(y: animateSubtitle ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.8), value: animateSubtitle)
                    
                    Spacer()
                    
                    // Get Started Butonu
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            showCountryList = true
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text("Başlayalım")
                                .font(.system(size: 20, weight: .semibold))
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple, Color.pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                        )
                    }
                    .scaleEffect(animateButton ? 1.0 : 0.8)
                    .opacity(animateButton ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(1.2), value: animateButton)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            animateTitle = true
            animateSubtitle = true
            animateButton = true
        }
    }
}
// MARK: - Ülke Modeli
struct Country {
    let name: String
    let flag: String
    let colors: [Color]
    let desserts: [Dessert]
}

struct Dessert {
    let name: String
    let imageURL: String
    let description: String
    let cookingTime: Int
    let servings: Int
    let difficulty: String
    let ingredients: [String]
    let instructions: [String]
    let videoURL: String
}

// MARK: - Country Data Singleton
class CountryData {
    static let shared = CountryData()
    
    let countries = [
        Country(
            name: "Türkiye",
            flag: "🇹🇷",
            colors: [Color.red, Color.white],
            desserts: [
                Dessert(
                    name: "Baklava",
                    imageURL: "https://cdn.yemek.com/mnresize/1250/833/uploads/2014/06/baklava-asama-10.jpg",
                    description: "Çıtır yufka ve antep fıstığından yapılan geleneksel Türk tatlısı",
                    cookingTime: 60,
                    servings: 8,
                    difficulty: "Orta",
                    ingredients: ["Yufka", "Antep Fıstığı", "Tereyağı", "Şeker", "Su", "Limon"],
                    instructions: ["Yufkaları yağlayın", "Fıstıkları serpin", "Fırında pişirin", "Şerbeti dökün"],
                    videoURL: "https://www.youtube.com/watch?v=baklava123"
                ),
                Dessert(
                    name: "Künefe",
                    imageURL: "https://cdn.yemek.com/mnresize/1250/833/uploads/2022/03/kunefe-yemekcom.jpg",
                    description: "Peynirli ve şerbetli sıcak tatlı",
                    cookingTime: 30,
                    servings: 4,
                    difficulty: "Kolay",
                    ingredients: ["Kadayıf", "Peynir", "Şeker", "Su", "Tereyağı"],
                    instructions: ["Kadayıfı hazırlayın", "Peyniri ekleyin", "Pişirin", "Şerbet dökün"],
                    videoURL: "https://www.youtube.com/watch?v=kunefe123"
                ),
                Dessert(
                    name: "Sütlaç",
                    imageURL: "https://cdn.yemek.com/mnresize/1250/833/uploads/2014/06/sutlac.jpg",
                    description: "Fırında pişirilen geleneksel sütlü tatlı",
                    cookingTime: 45,
                    servings: 6,
                    difficulty: "Kolay",
                    ingredients: ["Süt", "Pirinç", "Şeker", "Vanilya", "Tarçın"],
                    instructions: ["Pirinç haşlayın", "Süt ekleyin", "Fırına verin", "Tarçın serpin"],
                    videoURL: "https://www.youtube.com/watch?v=sutlac123"
                )
            ]
        ),
        Country(
            name: "İtalya",
            flag: "🇮🇹",
            colors: [Color.green, Color.white, Color.red],
            desserts: [
                Dessert(
                    name: "Tiramisu",
                    imageURL: "https://img.elele.com.tr/rcman/Cw780h439q95gc/storage/files/images/2021/11/20/whatsapp-image-2021-11-19-at-12-o5Xy_cover.jpg",
                    description: "Kahve aromalı geleneksel İtalyan tatlısı",
                    cookingTime: 30,
                    servings: 8,
                    difficulty: "Orta",
                    ingredients: ["Mascarpone", "Ladyfinger", "Espresso", "Kakao", "Yumurta"],
                    instructions: ["Kahve hazırlayın", "Krema yapın", "Katmanları dizin", "Buzdolabında bekletin"],
                    videoURL: "https://www.youtube.com/watch?v=tiramisu123"
                ),
                Dessert(
                    name: "Gelato",
                    imageURL: "https://delishglobe.com/wp-content/uploads/2024/09/Gelato-1.png",
                    description: "Geleneksel İtalyan dondurması",
                    cookingTime: 120,
                    servings: 6,
                    difficulty: "Orta",
                    ingredients: ["Süt", "Krema", "Şeker", "Yumurta", "Vanilya"],
                    instructions: ["Krema yapın", "Karıştırın", "Dondurma makinesine atın", "Dondurun"],
                    videoURL: "https://www.youtube.com/watch?v=gelato123"
                )
            ]
        ),
        Country(
            name: "Fransa",
            flag: "🇫🇷",
            colors: [Color.blue, Color.white, Color.red],
            desserts: [
                Dessert(
                    name: "Macaron",
                    imageURL: "https://emaarskyview.com/wp-content/uploads/2024/10/macaron.webp",
                    description: "Renkli Fransız kurabiyesi",
                    cookingTime: 90,
                    servings: 24,
                    difficulty: "Zor",
                    ingredients: ["Badem Unu", "Şeker", "Yumurta Akı", "Gıda Boyası"],
                    instructions: ["Macaronage yapın", "Sıkın", "Pişirin", "Krema ekleyin"],
                    videoURL: "https://www.youtube.com/watch?v=macaron123"
                )
            ]
        ),
        Country(
            name: "Japonya",
            flag: "🇯🇵",
            colors: [Color.red, Color.white],
            desserts: [
                Dessert(
                    name: "Mochi",
                    imageURL: "https://www.datocms-assets.com/43891/1670829320-mochi.jpg",
                    description: "Pirinç hamurlu Japon tatlısı",
                    cookingTime: 45,
                    servings: 12,
                    difficulty: "Orta",
                    ingredients: ["Pirinç Unu", "Şeker", "Su", "Fasulye Ezmesi"],
                    instructions: ["Hamuru yapın", "Şekillendirin", "İç harcı ekleyin", "Tamamlayın"],
                    videoURL: "https://www.youtube.com/watch?v=mochi123"
                )
            ]
        ),
        Country(
            name: "Belçika",
            flag: "🇧🇪",
            colors: [Color.black, Color.yellow, Color.red],
            desserts: [
                Dessert(
                    name: "Waffle",
                    imageURL: "https://www.the-girl-who-ate-everything.com/wp-content/uploads/2024/03/belgian-waffle-recipe-003.jpg",
                    description: "Geleneksel Belçika waffle'ı",
                    cookingTime: 20,
                    servings: 4,
                    difficulty: "Kolay",
                    ingredients: ["Un", "Süt", "Yumurta", "Tereyağı", "Şeker"],
                    instructions: ["Hamuru hazırlayın", "Waffle makinesinde pişirin", "Süsleyin"],
                    videoURL: "https://www.youtube.com/watch?v=waffle123"
                )
            ]
        ),
        Country(
            name: "Amerika",
            flag: "🇺🇸",
            colors: [Color.red, Color.white, Color.blue],
            desserts: [
                Dessert(
                    name: "Cheesecake",
                    imageURL: "https://d2lswn7b0fl4u2.cloudfront.net/photos/pg-a-slice-of-cheesecake-with-berries-on-top-1608056709.jpg",
                    description: "Kremsi Amerikan cheesecake'i",
                    cookingTime: 90,
                    servings: 10,
                    difficulty: "Orta",
                    ingredients: ["Krem Peynir", "Şeker", "Yumurta", "Bisküvi", "Tereyağı"],
                    instructions: ["Tabanı hazırlayın", "Krema yapın", "Pişirin", "Soğutun"],
                    videoURL: "https://www.youtube.com/watch?v=cheesecake123"
                )
            ]
        ),
        Country(
            name: "Hindistan",
            flag: "🇮🇳",
            colors: [Color.orange, Color.white, Color.green],
            desserts: [
                Dessert(
                    name: "Gulab Jamun",
                    imageURL: "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcQcQ5ajWr8uH8ucnNcpqa9irsm0aTGEDZN4hw&s",
                    description: "Şerbetli Hint tatlısı",
                    cookingTime: 45,
                    servings: 8,
                    difficulty: "Orta",
                    ingredients: ["Süt Tozu", "Un", "Şeker", "Gül Suyu", "Yağ"],
                    instructions: ["Hamuru yapın", "Topları şekillendirin", "Kızartın", "Şerbete batırın"],
                    videoURL: "https://www.youtube.com/watch?v=gulabjamun123"
                )
            ]
        ),
        Country(
            name: "Yunanistan",
            flag: "🇬🇷",
            colors: [Color.blue, Color.white],
            desserts: [
                Dessert(
                    name: "Baklava",
                    imageURL: "https://www.themediterraneandish.com/wp-content/uploads/2020/02/Greek-baklava-recipe-7.jpg",
                    description: "Yunan usulü baklava",
                    cookingTime: 75,
                    servings: 12,
                    difficulty: "Orta",
                    ingredients: ["Phyllo", "Ceviz", "Bal", "Tereyağı", "Tarçın"],
                    instructions: ["Yufkaları yağlayın", "Ceviz serpin", "Dilimleyin", "Pişirin"],
                    videoURL: "https://www.youtube.com/watch?v=greekbaklava123"
                )
            ]
        ),
        Country(
            name: "İspanya",
            flag: "🇪🇸",
            colors: [Color.red, Color.yellow],
            desserts: [
                Dessert(
                    name: "Churros",
                    imageURL: "https://ia.tmgrup.com.tr/2addbe/483/272/0/0/798/450?u=https://i.tmgrup.com.tr/sfr/2024/12/30/churros-1735579557697.jpg",
                    description: "Çikolata soslu İspanyol tatlısı",
                    cookingTime: 30,
                    servings: 6,
                    difficulty: "Kolay",
                    ingredients: ["Un", "Su", "Tuz", "Yağ", "Çikolata"],
                    instructions: ["Hamuru yapın", "Sıkın", "Kızartın", "Çikolata ile servis edin"],
                    videoURL: "https://www.youtube.com/watch?v=churros123"
                )
            ]
        ),
        Country(
            name: "Brezilya",
            flag: "🇧🇷",
            colors: [Color.green, Color.yellow, Color.blue],
            desserts: [
                Dessert(
                    name: "Brigadeiro",
                    imageURL: "https://upload.wikimedia.org/wikipedia/commons/a/a4/Brigadeiro.jpg",
                    description: "Çikolatalı Brezilya topları",
                    cookingTime: 20,
                    servings: 15,
                    difficulty: "Kolay",
                    ingredients: ["Yoğun Süt", "Kakao", "Tereyağı", "Çikolata Granülü"],
                    instructions: ["Karıştırın", "Pişirin", "Soğutun", "Topları yapın"],
                    videoURL: "https://www.youtube.com/watch?v=brigadeiro123"
                )
            ]
        ),
        Country(
            name: "Avusturya",
            flag: "🇦🇹",
            colors: [Color.red, Color.white],
            desserts: [
                Dessert(
                    name: "Sachertorte",
                    imageURL: "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcS0LsR8KB4QJUub9FBhYh0M3w_rQMP1vlTSTg&s",
                    description: "Kayısılı Avusturya çikolata keki",
                    cookingTime: 120,
                    servings: 12,
                    difficulty: "Zor",
                    ingredients: ["Çikolata", "Tereyağı", "Şeker", "Yumurta", "Kayısı Reçeli"],
                    instructions: ["Kek yapın", "Reçel sürün", "Çikolata ile kaplayın", "Dinlendirin"],
                    videoURL: "https://www.youtube.com/watch?v=sachertorte123"
                )
            ]
        ),
        Country(
            name: "Meksika",
            flag: "🇲🇽",
            colors: [Color.green, Color.white, Color.red],
            desserts: [
                Dessert(
                    name: "Tres Leches",
                    imageURL: "https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRjax1G_250idnrIxDT43D_pT2r2Slk3Nt02A&s",
                    description: "Üç sütlü Meksika keki",
                    cookingTime: 60,
                    servings: 10,
                    difficulty: "Orta",
                    ingredients: ["Un", "Süt", "Krema", "Yoğun Süt", "Yumurta"],
                    instructions: ["Kek yapın", "Süt karışımı hazırlayın", "Döküp emdir", "Süsleyin"],
                    videoURL: "https://www.youtube.com/watch?v=tresleches123"
                )
            ]
        )
    ]
    
    private init() {}
}
// MARK: - Ülke Listesi Sayfası
struct CountryListView: View {
    @State private var animateCards = false
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 20) {
                ForEach(Array(CountryData.shared.countries.enumerated()), id: \.offset) { index, country in
                    NavigationLink(destination: CountryDetailView(country: country)) {
                        CountryCard(country: country)
                            .scaleEffect(animateCards ? 1.0 : 0.8)
                            .opacity(animateCards ? 1 : 0)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(index) * 0.1), value: animateCards)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
        }
        .navigationTitle("Ülkeler")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            animateCards = true
        }
    }
}

// MARK: - Ülke Kartı
struct CountryCard: View {
    let country: Country
    
    var body: some View {
        VStack(spacing: 12) {
            Text(country.flag)
                .font(.system(size: 50))
            
            Text(country.name)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            country.colors.first?.opacity(0.3) ?? Color.clear,
                            country.colors.last?.opacity(0.1) ?? Color.clear,
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(country.colors.first?.opacity(0.3) ?? Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Ülke Detay Sayfası
struct CountryDetailView: View {
    let country: Country
    @State private var animateContent = false
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Başlık Bölümü
                VStack(spacing: 16) {
                    Text(country.flag)
                        .font(.system(size: 80))
                        .scaleEffect(animateContent ? 1.0 : 0.5)
                        .animation(.spring(response: 0.8, dampingFraction: 0.6), value: animateContent)
                    
                    Text("\(country.name) Tatlıları")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(country.colors.first ?? .primary)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateContent)
                }
                .padding(.vertical, 20)
                .background(
                    LinearGradient(
                        colors: country.colors.map { $0.opacity(0.2) } + [Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .cornerRadius(20)
                )
                
                // Tatlı Listesi
                ForEach(Array(country.desserts.enumerated()), id: \.offset) { index, dessert in
                    NavigationLink(destination: DessertDetailView(
                        dessert: dessert,
                        countryColors: country.colors,
                        countryName: country.name
                    )) {
                        DessertCard(dessert: dessert, colors: country.colors)
                            .opacity(animateContent ? 1 : 0)
                            .offset(x: animateContent ? 0 : (index % 2 == 0 ? -50 : 50))
                            .animation(.easeOut(duration: 0.6).delay(0.5 + Double(index) * 0.1), value: animateContent)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    country.colors.first?.opacity(0.1) ?? Color.clear,
                    country.colors.last?.opacity(0.05) ?? Color.clear,
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            animateContent = true
        }
    }
}

// MARK: - Tatlı Kartı
struct DessertCard: View {
    let dessert: Dessert
    let colors: [Color]
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with favorite button
            HStack {
                Spacer()
                Button(action: {
                    favoritesManager.toggleFavorite(dessert.name)
                }) {
                    Image(systemName: favoritesManager.isFavorite(dessert.name) ? "heart.fill" : "heart")
                        .foregroundColor(favoritesManager.isFavorite(dessert.name) ? .red : .gray)
                        .font(.title2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Gerçek resim yüklenecek alan
            AsyncImage(url: URL(string: dessert.imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.first?.opacity(0.3) ?? Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(colors.first ?? .gray)
                    )
            }
            .frame(height: 150)
            .clipped()
            .cornerRadius(12)
            .padding(.horizontal, 16)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(dessert.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(colors.first ?? .primary)
                
                Text(dessert.description)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundColor(colors.first ?? .gray)
                        Text("\(dessert.cookingTime) dk")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .foregroundColor(colors.first ?? .gray)
                        Text("\(dessert.servings) kişi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(colors.first ?? .gray)
                        Text(dessert.difficulty)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colors.first?.opacity(0.3) ?? Color.clear, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
    }
}
// MARK: - Kalori Hesaplayıcı View
struct CalorieCalculatorView: View {
    let dessertName: String
    @State private var selectedPortions: Double = 1.0
    @Binding var isPresented: Bool
    
    private var caloriesPerServing: Int {
        CalorieCalculator.calculateCaloriesPerServing(for: dessertName)
    }
    
    private var portionWeight: Int {
        CalorieCalculator.getPortionWeight(for: dessertName)
    }
    
    private var totalCalories: Int {
        Int(Double(caloriesPerServing) * selectedPortions)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                VStack(spacing: 20) {
                    Text("🔥")
                        .font(.system(size: 60))
                    
                    Text("Kalori Hesaplayıcısı")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(dessertName)
                        .font(.title3)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
                
                VStack(spacing: 20) {
                    // Porsiyon Bilgisi
                    VStack(spacing: 12) {
                        Text("1 Porsiyon Bilgileri")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 30) {
                            VStack {
                                Text("\(portionWeight)g")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("Ağırlık")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack {
                                Text("\(caloriesPerServing)")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.orange)
                                Text("Kalori")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Porsiyon Seçici
                    VStack(spacing: 15) {
                        Text("Kaç porsiyon tüketeceksiniz?")
                            .font(.headline)
                        
                        HStack {
                            Button(action: {
                                if selectedPortions > 0.5 {
                                    selectedPortions -= 0.5
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            
                            Text(selectedPortions == floor(selectedPortions) ?
                                 String(format: "%.0f", selectedPortions) :
                                 String(format: "%.1f", selectedPortions))
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(minWidth: 60)
                            
                            Button(action: {
                                if selectedPortions < 10 {
                                    selectedPortions += 0.5
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        // Slider
                        VStack(spacing: 8) {
                            Slider(value: $selectedPortions, in: 0.5...5.0, step: 0.5)
                                .accentColor(.blue)
                            
                            HStack {
                                Text("0.5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    )
                    
                    // Toplam Kalori Gösterimi
                    VStack(spacing: 12) {
                        Text("Toplam Kalori")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("\(totalCalories)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        
                        Text("kalori")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        // Aktivite karşılaştırması
                        VStack(spacing: 8) {
                            Text("Bu kaloriyi yakmak için:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 20) {
                                ActivityComparison(
                                    icon: "figure.walk",
                                    activity: "Yürüyüş",
                                    duration: totalCalories / 5,
                                    unit: "dk"
                                )
                                
                                ActivityComparison(
                                    icon: "figure.run",
                                    activity: "Koşu",
                                    duration: totalCalories / 10,
                                    unit: "dk"
                                )
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.1), Color.red.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(16)
                }
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Kapat") {
                    isPresented = false
                }
            )
        }
    }
}

// MARK: - Aktivite Karşılaştırma Bileşeni
struct ActivityComparison: View {
    let icon: String
    let activity: String
    let duration: Int
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            Text("\(duration) \(unit)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(activity)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
// MARK: - Achievement Popup View
struct AchievementPopupView: View {
    let achievement: Achievement
    @Binding var isPresented: Bool
    @State private var animateIcon = false
    @State private var animateContent = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 20) {
                // Icon with animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(animateIcon ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animateIcon)
                    
                    Image(systemName: achievement.icon)
                        .font(.system(size: 40))
                        .foregroundColor(.orange)
                        .scaleEffect(animateIcon ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: animateIcon)
                }
                
                VStack(spacing: 12) {
                    Text("🎉 Başarım Kazanıldı!")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: animateContent)
                    
                    Text(achievement.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.5), value: animateContent)
                    
                    Text(achievement.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.7), value: animateContent)
                }
                
                Button(action: {
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    Text("Harika!")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(25)
                }
                .opacity(animateContent ? 1 : 0)
                .scaleEffect(animateContent ? 1 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.9), value: animateContent)
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
            .scaleEffect(isPresented ? 1 : 0.8)
            .opacity(isPresented ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isPresented)
        }
        .onAppear {
            animateIcon = true
            animateContent = true
            
            // 3 saniye sonra otomatik kapat
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isPresented = false
                }
            }
        }
    }
}

// MARK: - Achievements View
struct AchievementsView: View {
    @ObservedObject var achievementManager = AchievementManager.shared
    @State private var selectedFilter: AchievementFilter = .all
    
    enum AchievementFilter: String, CaseIterable {
        case all = "Tümü"
        case unlocked = "Kazanılan"
        case locked = "Kilitli"
    }
    
    var filteredAchievements: [Achievement] {
        switch selectedFilter {
        case .all:
            return achievementManager.achievements
        case .unlocked:
            return achievementManager.achievements.filter { $0.isUnlocked }
        case .locked:
            return achievementManager.achievements.filter { !$0.isUnlocked }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats Header
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    StatCard(
                        title: "Kazanılan",
                        value: "\(achievementManager.achievements.filter { $0.isUnlocked }.count)",
                        total: "\(achievementManager.achievements.count)",
                        color: .green
                    )
                    
                    StatCard(
                        title: "İlerleme",
                        value: String(format: "%.0f%%", Double(achievementManager.achievements.filter { $0.isUnlocked }.count) / Double(achievementManager.achievements.count) * 100),
                        total: "",
                        color: .blue
                    )
                }
                
                // Filter Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(AchievementFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // Achievements List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredAchievements) { achievement in
                        AchievementCard(achievement: achievement)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Başarımlar")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Achievement Card
struct AchievementCard: View {
    let achievement: Achievement
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(achievement.isUnlocked ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: achievement.icon)
                    .font(.title2)
                    .foregroundColor(achievement.isUnlocked ? .orange : .gray)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(achievement.title)
                        .font(.headline)
                        .foregroundColor(achievement.isUnlocked ? .primary : .secondary)
                    
                    Spacer()
                    
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                }
                
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                // Progress Bar
                if !achievement.isUnlocked {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(achievement.progress)/\(achievement.targetValue)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", achievement.progressPercentage * 100))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        ProgressView(value: achievement.progressPercentage)
                            .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                            .scaleEffect(y: 0.8)
                    }
                } else if let unlockedDate = achievement.unlockedDate {
                    Text("Kazanıldı: \(DateFormatter.achievementFormatter.string(from: unlockedDate))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(achievement.isUnlocked ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .opacity(achievement.isUnlocked ? 1.0 : 0.7)
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let title: String
    let value: String
    let total: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                if !total.isEmpty {
                    Text("/\(total)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
// MARK: - Search View
struct SearchView: View {
    @State private var searchText = ""
    @State private var selectedDifficulty = "Hepsi"
    @State private var maxCookingTime = 120
    @State private var showFilters = false
    
    let difficulties = ["Hepsi", "Kolay", "Orta", "Zor"]
    
    var filteredDesserts: [(Country, Dessert)] {
        var allDesserts: [(Country, Dessert)] = []
        
        for country in CountryData.shared.countries {
            for dessert in country.desserts {
                allDesserts.append((country, dessert))
            }
        }
        
        return allDesserts.filter { country, dessert in
            let matchesSearch = searchText.isEmpty ||
                              dessert.name.localizedCaseInsensitiveContains(searchText) ||
                              country.name.localizedCaseInsensitiveContains(searchText)
            
            let matchesDifficulty = selectedDifficulty == "Hepsi" || dessert.difficulty == selectedDifficulty
            let matchesTime = dessert.cookingTime <= maxCookingTime
            
            return matchesSearch && matchesDifficulty && matchesTime
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Tatlı veya ülke ara...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                Button(action: { showFilters.toggle() }) {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Filtreler")
                        Spacer()
                        Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                
                if showFilters {
                    VStack(spacing: 16) {
                        // Zorluk Filtresi
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Zorluk Seviyesi")
                                .font(.headline)
                            
                            Picker("Zorluk", selection: $selectedDifficulty) {
                                ForEach(difficulties, id: \.self) { difficulty in
                                    Text(difficulty).tag(difficulty)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        
                        // Süre Filtresi
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Maksimum Süre: \(maxCookingTime) dakika")
                                .font(.headline)
                            
                            Slider(value: Binding(
                                get: { Double(maxCookingTime) },
                                set: { maxCookingTime = Int($0) }
                            ), in: 10...120, step: 10)
                            .accentColor(.blue)
                        }
                    }
                    .padding(16)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            
            // Results
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(filteredDesserts.enumerated()), id: \.offset) { index, item in
                        let (country, dessert) = item
                        NavigationLink(destination: DessertDetailView(
                            dessert: dessert,
                            countryColors: country.colors,
                            countryName: country.name
                        )) {
                            SearchResultCard(country: country, dessert: dessert)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Arama")
        .navigationBarTitleDisplayMode(.large)
        .animation(.easeInOut, value: showFilters)
    }
}

// MARK: - Search Result Card
struct SearchResultCard: View {
    let country: Country
    let dessert: Dessert
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: URL(string: dessert.imageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 12)
                    .fill(country.colors.first?.opacity(0.3) ?? Color.gray.opacity(0.3))
                    .overlay(
                        ProgressView()
                            .tint(country.colors.first ?? .gray)
                    )
            }
            .frame(width: 80, height: 80)
            .clipped()
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(country.flag)
                        .font(.title2)
                    Text(country.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        favoritesManager.toggleFavorite(dessert.name)
                    }) {
                        Image(systemName: favoritesManager.isFavorite(dessert.name) ? "heart.fill" : "heart")
                            .foregroundColor(favoritesManager.isFavorite(dessert.name) ? .red : .gray)
                    }
                }
                
                Text(dessert.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(dessert.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 16) {
                    Label("\(dessert.cookingTime) dk", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(dessert.difficulty, systemImage: "star")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
// MARK: - Favorites View
struct FavoritesView: View {
    @EnvironmentObject var favoritesManager: FavoritesManager
    
    var favoriteDesserts: [(Country, Dessert)] {
        var allDesserts: [(Country, Dessert)] = []
        
        for country in CountryData.shared.countries {
            for dessert in country.desserts {
                if favoritesManager.isFavorite(dessert.name) {
                    allDesserts.append((country, dessert))
                }
            }
        }
        
        return allDesserts
    }
    
    var body: some View {
        Group {
            if favoriteDesserts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("Henüz favori tatlınız yok")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text("Beğendiğiniz tarifleri kalp ikonuna tıklayarak favorilerinize ekleyebilirsiniz")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(favoriteDesserts.enumerated()), id: \.offset) { index, item in
                            let (country, dessert) = item
                            NavigationLink(destination: DessertDetailView(
                                dessert: dessert,
                                countryColors: country.colors,
                                countryName: country.name
                            )) {
                                SearchResultCard(country: country, dessert: dessert)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Favoriler")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Timer View
struct TimerView: View {
    @StateObject private var timerManager = TimerManager()
    @State private var selectedMinutes = 5
    
    let timerOptions = [1, 5, 10, 15, 20, 30, 45, 60, 90, 120]
    
    var body: some View {
        VStack(spacing: 30) {
            // Timer Display
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 20)
                        .frame(width: 200, height: 200)
                    
                    Circle()
                        .trim(from: 0, to: timerManager.progress)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .frame(width: 200, height: 200)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear, value: timerManager.progress)
                    
                    VStack {
                        if timerManager.isActive || timerManager.timeRemaining > 0 {
                            Text(timerManager.formattedTime)
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        } else {
                            Text("Timer")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if timerManager.timeRemaining == 0 && !timerManager.isActive && timerManager.totalTime > 0 {
                    Text("Süre Doldu! 🎉")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            
            if !timerManager.isActive && timerManager.timeRemaining == 0 {
                // Timer Selection
                VStack(spacing: 20) {
                    Text("Süre Seçin")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Picker("Dakika", selection: $selectedMinutes) {
                        ForEach(timerOptions, id: \.self) { minutes in
                            Text("\(minutes) dk").tag(minutes)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(height: 120)
                    
                    Button(action: {
                        timerManager.startTimer(minutes: selectedMinutes)
                        AchievementManager.shared.trackTimerUsage() // Achievement tracking
                    }) {
                        Text("Başlat")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 200, height: 50)
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(25)
                    }
                }
            } else {
                // Timer Controls
                HStack(spacing: 20) {
                    if timerManager.isActive {
                        Button(action: {
                            timerManager.pauseTimer()
                        }) {
                            Image(systemName: "pause.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                    } else if timerManager.timeRemaining > 0 {
                        Button(action: {
                            timerManager.resumeTimer()
                        }) {
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                    
                    Button(action: {
                        timerManager.stopTimer()
                    }) {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Zamanlayıcı")
        .navigationBarTitleDisplayMode(.large)
    }
}
// MARK: - Tatlı Detay Sayfası (Achievement Tracking ile)
struct DessertDetailView: View {
    let dessert: Dessert
    let countryColors: [Color]
    let countryName: String
    
    @State private var showFullRecipe = false
    @State private var showCalorieCalculator = false
    @State private var portionMultiplier = 1.0
    @EnvironmentObject var favoritesManager: FavoritesManager
    @StateObject private var timerManager = TimerManager()
    
    // Achievement tracking için
    @State private var hasTrackedView = false
    
    var adjustedIngredients: [String] {
        if portionMultiplier == 1.0 {
            return dessert.ingredients
        }
        return dessert.ingredients.map { ingredient in
            return "\(ingredient) (x\(String(format: "%.1f", portionMultiplier)))"
        }
    }
    
    var adjustedServings: Int {
        return Int(Double(dessert.servings) * portionMultiplier)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Başlık ve Resim Bölümü
                VStack(spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: URL(string: dessert.imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(countryColors.first?.opacity(0.3) ?? Color.gray.opacity(0.3))
                                .overlay(
                                    ProgressView()
                                        .tint(countryColors.first ?? .gray)
                                )
                        }
                        .frame(height: 250)
                        .clipped()
                        .cornerRadius(20)
                        
                        // Favorite button overlay
                        Button(action: {
                            favoritesManager.toggleFavorite(dessert.name)
                        }) {
                            Image(systemName: favoritesManager.isFavorite(dessert.name) ? "heart.fill" : "heart")
                                .foregroundColor(favoritesManager.isFavorite(dessert.name) ? .red : .white)
                                .font(.title2)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    
                    Text(dessert.name)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(countryColors.first ?? .primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                
                // Bilgi Kartları
                HStack(spacing: 12) {
                    InfoCard(icon: "clock", title: "Süre", value: "\(dessert.cookingTime) dk", color: countryColors.first ?? .blue)
                    InfoCard(icon: "person.2", title: "Porsiyon", value: "\(adjustedServings) kişi", color: countryColors.first ?? .blue)
                    InfoCard(icon: "star", title: "Zorluk", value: dessert.difficulty, color: countryColors.first ?? .blue)
                }
                .padding(.horizontal)
                
                // Timer ve Kalori Hesaplayıcı Butonları
                HStack(spacing: 12) {
                    Button(action: {
                        timerManager.startTimer(minutes: dessert.cookingTime)
                        AchievementManager.shared.trackTimerUsage() // Achievement tracking
                    }) {
                        HStack {
                            Image(systemName: "timer")
                            Text("Timer Başlat")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .cornerRadius(20)
                    }
                    
                    Button(action: {
                        showCalorieCalculator = true
                        AchievementManager.shared.trackCalorieCalculation() // Achievement tracking
                    }) {
                        HStack {
                            Image(systemName: "flame.fill")
                            Text("Kalori Hesapla")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(countryColors.first ?? .blue)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(countryColors.first ?? .blue, lineWidth: 2)
                        )
                    }
                }
                .padding(.horizontal)
                
                // Timer Display (if active)
                if timerManager.isActive || timerManager.timeRemaining > 0 {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Pişirme Zamanlayıcısı")
                                .font(.headline)
                            Spacer()
                            Text(timerManager.formattedTime)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .foregroundColor(timerManager.timeRemaining <= 60 ? .red : .primary)
                        }
                        
                        ProgressView(value: timerManager.progress)
                            .accentColor(timerManager.timeRemaining <= 60 ? .red : .blue)
                        
                        HStack {
                            if timerManager.isActive {
                                Button("Duraklat") {
                                    timerManager.pauseTimer()
                                }
                                .foregroundColor(.orange)
                            } else if timerManager.timeRemaining > 0 {
                                Button("Devam Et") {
                                    timerManager.resumeTimer()
                                }
                                .foregroundColor(.green)
                            }
                            
                            Spacer()
                            
                            Button("Durdur") {
                                timerManager.stopTimer()
                            }
                            .foregroundColor(.red)
                        }
                        .font(.system(size: 16, weight: .medium))
                        
                        if timerManager.timeRemaining == 0 && timerManager.totalTime > 0 {
                            Text("🎉 Süre Doldu! Tatlınız hazır!")
                                .font(.headline)
                                .foregroundColor(.green)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                
                // Açıklama
                VStack(alignment: .leading, spacing: 12) {
                    Text("Açıklama")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(countryColors.first ?? .primary)
                    
                    Text(dessert.description)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                .padding(.horizontal)
                
                // Malzemeler
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Malzemeler")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(countryColors.first ?? .primary)
                        
                        if portionMultiplier != 1.0 {
                            Spacer()
                            Text("(\(adjustedServings) kişilik)")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    
                    ForEach(adjustedIngredients, id: \.self) { ingredient in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(countryColors.first?.opacity(0.3) ?? Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            Text(ingredient)
                                .font(.system(size: 16))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                
                // Tarif Butonu
                Button(action: {
                    showFullRecipe.toggle()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: showFullRecipe ? "chevron.up" : "chevron.down")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text(showFullRecipe ? "Tarifi Gizle" : "Tarifin Tamamını Göster")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: countryColors.count >= 2 ? countryColors : [countryColors.first ?? .blue, countryColors.first?.opacity(0.7) ?? .blue.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    )
                }
                .padding(.horizontal)
                
                // Tarif Adımları
                if showFullRecipe {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Yapılışı")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(countryColors.first ?? .primary)
                        
                        ForEach(Array(dessert.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top, spacing: 16) {
                                Text("\(index + 1)")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(countryColors.first ?? .blue)
                                    )
                                
                                Text(instruction)
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .lineSpacing(4)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale))
                }
                
                // Video Butonu (eğer varsa)
                if !dessert.videoURL.isEmpty {
                    Button(action: {
                        if let url = URL(string: dessert.videoURL) {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 20))
                            
                            Text("Video İzle")
                                .font(.system(size: 18, weight: .medium))
                        }
                        .foregroundColor(countryColors.first ?? .blue)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(countryColors.first ?? .blue, lineWidth: 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 25)
                                        .fill(Color(.systemBackground))
                                )
                        )
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(
            LinearGradient(
                colors: [
                    countryColors.first?.opacity(0.05) ?? Color.clear,
                    Color(.systemGroupedBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCalorieCalculator) {
            CalorieCalculatorView(
                dessertName: dessert.name,
                isPresented: $showCalorieCalculator
            )
        }
        .onAppear {
            // Achievement tracking - sadece bir kez takip et
            if !hasTrackedView {
                AchievementManager.shared.trackDessertView(dessert.name, country: countryName)
                hasTrackedView = true
            }
        }
    }
}

// MARK: - DessertDetailView için yeni init
extension DessertDetailView {
    init(dessert: Dessert, countryColors: [Color], countryName: String = "") {
        self.dessert = dessert
        self.countryColors = countryColors
        self.countryName = countryName
    }
}
// MARK: - Bilgi Kartı
struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(FavoritesManager.shared)
        .environmentObject(AchievementManager.shared)
}
