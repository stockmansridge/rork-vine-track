import Foundation
import Supabase

private func envValue(_ key: String) -> String {
    Config.allValues[key] ?? ""
}

private let SUPABASE_URL_OVERRIDE = "https://vuyxofjretznwslicanv.supabase.co"

private func resolvedSupabaseURL() -> String {
    if !SUPABASE_URL_OVERRIDE.isEmpty { return SUPABASE_URL_OVERRIDE }
    return envValue("EXPO_PUBLIC_SUPABASE_URL")
}

nonisolated(unsafe) let supabase: SupabaseClient = {
    let url = resolvedSupabaseURL()
    let key = envValue("EXPO_PUBLIC_SUPABASE_ANON_KEY")
    print("[Config] SUPABASE_URL = \(url)")
    print("[Config] SUPABASE_ANON_KEY present = \(!key.isEmpty)")

    return SupabaseClient(
        supabaseURL: URL(string: url.isEmpty ? "https://placeholder.supabase.co" : url)!,
        supabaseKey: key.isEmpty ? "placeholder" : key
    )
}()

var isSupabaseConfigured: Bool {
    let url = resolvedSupabaseURL()
    let key = envValue("EXPO_PUBLIC_SUPABASE_ANON_KEY")
    return !url.isEmpty && !key.isEmpty && !url.contains("placeholder")
}
