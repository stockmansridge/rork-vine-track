import Foundation
import Supabase

private func envValue(_ key: String) -> String {
    Config.allValues[key] ?? ""
}

nonisolated(unsafe) let supabase: SupabaseClient = {
    let url = envValue("EXPO_PUBLIC_SUPABASE_URL")
    let key = envValue("EXPO_PUBLIC_SUPABASE_ANON_KEY")

    return SupabaseClient(
        supabaseURL: URL(string: url.isEmpty ? "https://placeholder.supabase.co" : url)!,
        supabaseKey: key.isEmpty ? "placeholder" : key
    )
}()

var isSupabaseConfigured: Bool {
    let url = envValue("EXPO_PUBLIC_SUPABASE_URL")
    let key = envValue("EXPO_PUBLIC_SUPABASE_ANON_KEY")
    return !url.isEmpty && !key.isEmpty && !url.contains("placeholder")
}
