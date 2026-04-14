import Foundation

nonisolated struct ChemicalRateInfo: Codable, Sendable {
    let label: String
    let value: Double
}

nonisolated struct ChemicalInfoResponse: Codable, Sendable {
    let activeIngredient: String
    let brand: String
    let chemicalGroup: String
    let labelURL: String
    let primaryUse: String
    let ratesPerHectare: [ChemicalRateInfo]?
    let ratesPer100L: [ChemicalRateInfo]?
    let formType: String?
    let modeOfAction: String?

    var isLiquid: Bool {
        guard let form = formType?.lowercased() else { return true }
        return !form.contains("solid") && !form.contains("granul") && !form.contains("powder") && !form.contains("wettable") && !form.contains("dry") && !form.contains("wdg") && !form.contains("wg") && !form.contains("wp") && !form.contains("df")
    }

    var defaultUnit: ChemicalUnit {
        isLiquid ? .litres : .kilograms
    }
}

nonisolated struct ChemicalSearchResult: Identifiable, Codable, Sendable {
    var id: String { name }
    let name: String
    let activeIngredient: String
    let chemicalGroup: String
    let brand: String
    let primaryUse: String
    let modeOfAction: String
}

nonisolated struct ChemicalSearchResponse: Codable, Sendable {
    let results: [ChemicalSearchResult]
}

@MainActor
class ChemicalInfoService {
    static let shared = ChemicalInfoService()

    private func extractJSON(from text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let startBrace = cleaned.firstIndex(of: "{"),
           let endBrace = cleaned.lastIndex(of: "}") {
            cleaned = String(cleaned[startBrace...endBrace])
        } else if let startBracket = cleaned.firstIndex(of: "["),
                  let endBracket = cleaned.lastIndex(of: "]") {
            cleaned = String(cleaned[startBracket...endBracket])
        }

        return cleaned
    }

    nonisolated enum SearchError: Error, Sendable {
        case noResponse
        case parseFailed
    }

    func searchChemicals(query: String, country: String = "") async throws -> [ChemicalSearchResult] {
        let systemPrompt = "You are an agricultural chemical database expert. You respond ONLY with valid JSON, no markdown, no explanation, no code fences."

        let countryContext = country.isEmpty ? "" : " IMPORTANT: The vineyard is located in \(country). You MUST prioritize products that are registered, sold, and commonly used in \(country). List \(country)-registered brand names first. Use \(country)-based manufacturers and distributors (e.g. for Australia: Nufarm, Syngenta Australia, BASF Australia, Adama Australia, FMC Australasia, Bayer CropScience Australia). Only include international/generic products if fewer than 8 local \(country) products match the query."

        let prompt = """
        Search for agricultural/viticultural chemical products matching "\(query)".\(countryContext) Include fungicides, herbicides, insecticides, miticides, growth regulators, surfactants, adjuvants, and fertilisers. Consider brand names, active ingredients, and partial matches. Return up to 8 products as JSON:
        {"results":[{"name":"Product name","activeIngredient":"active ingredient(s)","chemicalGroup":"group","brand":"manufacturer","primaryUse":"primary use in vineyard e.g. Downy Mildew control, Nitrogen fertiliser, Botrytis prevention","modeOfAction":"MOA group code e.g. 3, 11, M5, 4A - use FRAC for fungicides, HRAC for herbicides, IRAC for insecticides, or empty string if unknown"}]}
        """

        let responseText = try await ToolkitHelper.sendChat(prompt: prompt, systemPrompt: systemPrompt)

        let cleaned = extractJSON(from: responseText)
        guard let jsonData = cleaned.data(using: .utf8) else { throw SearchError.parseFailed }

        if let decoded = try? JSONDecoder().decode(ChemicalSearchResponse.self, from: jsonData) {
            return decoded.results
        }

        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let resultsArray = json["results"] as? [[String: Any]] {
                let mapped = resultsArray.compactMap { item -> ChemicalSearchResult? in
                    guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                    return ChemicalSearchResult(
                        name: name,
                        activeIngredient: item["activeIngredient"] as? String ?? item["active_ingredient"] as? String ?? "",
                        chemicalGroup: item["chemicalGroup"] as? String ?? item["chemical_group"] as? String ?? "",
                        brand: item["brand"] as? String ?? item["manufacturer"] as? String ?? "",
                        primaryUse: item["primaryUse"] as? String ?? item["primary_use"] as? String ?? "",
                        modeOfAction: item["modeOfAction"] as? String ?? item["mode_of_action"] as? String ?? ""
                    )
                }
                if !mapped.isEmpty { return mapped }
            }
        }

        if let arr = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            let mapped = arr.compactMap { item -> ChemicalSearchResult? in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                return ChemicalSearchResult(
                    name: name,
                    activeIngredient: item["activeIngredient"] as? String ?? item["active_ingredient"] as? String ?? "",
                    chemicalGroup: item["chemicalGroup"] as? String ?? item["chemical_group"] as? String ?? "",
                    brand: item["brand"] as? String ?? item["manufacturer"] as? String ?? "",
                    primaryUse: item["primaryUse"] as? String ?? item["primary_use"] as? String ?? "",
                    modeOfAction: item["modeOfAction"] as? String ?? item["mode_of_action"] as? String ?? ""
                )
            }
            if !mapped.isEmpty { return mapped }
        }

        throw SearchError.parseFailed
    }

    func lookupChemicalInfo(productName: String, country: String = "") async throws -> ChemicalInfoResponse {
        let systemPrompt = "You are an agricultural chemical database expert. You respond ONLY with valid JSON, no markdown, no explanation, no code fences."

        let countryContext = country.isEmpty ? "" : " IMPORTANT: The vineyard is located in \(country). You MUST use the \(country)-registered version of this product. Provide \(country)-specific brand name, label rates, label URL, and regulatory data. If the product has a different brand name in \(country), use the \(country) brand name."

        let prompt = """
        Provide details for the agricultural product "\(productName)".\(countryContext) Find the closest match if exact name not found. Include recommended application rates for vineyard/viticultural use where available. Return as JSON:
        {"activeIngredient":"active ingredient(s)","brand":"manufacturer","chemicalGroup":"group classification","labelURL":"URL to label/SDS or empty string","primaryUse":"primary use in vineyard e.g. Downy Mildew control, Nitrogen fertiliser, Botrytis prevention","formType":"liquid or solid","modeOfAction":"MOA group code e.g. 3, 11, M5, 4A - use FRAC for fungicides, HRAC for herbicides, IRAC for insecticides, or empty string if unknown","ratesPerHectare":[{"label":"Standard rate","value":1.5}],"ratesPer100L":[{"label":"Standard rate","value":0.15}]}
        IMPORTANT: The "formType" field must be either "liquid" or "solid". Determine this from the product's physical form. Liquid products (EC, SC, SL, SE, EW, flowables, suspension concentrates, emulsifiable concentrates, soluble liquids) should be "liquid". Solid products (WG, WDG, WP, DF, granules, wettable powders, dry flowables, water dispersible granules) should be "solid".
        The ratesPerHectare array should contain recommended rates per hectare. For liquid products, values must be in Litres (L). For solid products, values must be in Kilograms (Kg). The ratesPer100L array should contain recommended rates per 100 litres of water, using the same unit convention. Include multiple rates if the label specifies different rates for different conditions (e.g. low/medium/high disease pressure). If rates are not available for a basis, return an empty array.
        """

        let responseText = try await ToolkitHelper.sendChat(prompt: prompt, systemPrompt: systemPrompt)

        let cleaned = extractJSON(from: responseText)
        guard let jsonData = cleaned.data(using: .utf8) else { throw SearchError.parseFailed }

        if let decoded = try? JSONDecoder().decode(ChemicalInfoResponse.self, from: jsonData) {
            return decoded
        }

        if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            let activeIngredient = json["activeIngredient"] as? String
                ?? json["active_ingredient"] as? String
                ?? ""
            let brand = json["brand"] as? String
                ?? json["manufacturer"] as? String
                ?? ""
            let chemicalGroup = json["chemicalGroup"] as? String
                ?? json["chemical_group"] as? String
                ?? ""
            let labelURL = json["labelURL"] as? String
                ?? json["label_url"] as? String
                ?? json["labelUrl"] as? String
                ?? ""
            let primaryUse = json["primaryUse"] as? String
                ?? json["primary_use"] as? String
                ?? ""
            let ratesPerHa = Self.parseRateInfoArray(json["ratesPerHectare"] ?? json["rates_per_hectare"])
            let ratesPer100L = Self.parseRateInfoArray(json["ratesPer100L"] ?? json["rates_per_100l"] ?? json["ratesPer100l"])
            let formType = json["formType"] as? String ?? json["form_type"] as? String
            let modeOfAction = json["modeOfAction"] as? String ?? json["mode_of_action"] as? String
            if !activeIngredient.isEmpty || !brand.isEmpty || !chemicalGroup.isEmpty {
                return ChemicalInfoResponse(activeIngredient: activeIngredient, brand: brand, chemicalGroup: chemicalGroup, labelURL: labelURL, primaryUse: primaryUse, ratesPerHectare: ratesPerHa, ratesPer100L: ratesPer100L, formType: formType, modeOfAction: modeOfAction)
            }
        }

        throw SearchError.parseFailed
    }

    private static func parseRateInfoArray(_ value: Any?) -> [ChemicalRateInfo] {
        guard let arr = value as? [[String: Any]] else { return [] }
        return arr.compactMap { item in
            guard let label = item["label"] as? String else { return nil }
            let val: Double
            if let d = item["value"] as? Double {
                val = d
            } else if let s = item["value"] as? String, let d = Double(s) {
                val = d
            } else {
                return nil
            }
            return ChemicalRateInfo(label: label, value: val)
        }
    }
}
