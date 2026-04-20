import Foundation

extension DataStore {

    // MARK: - Demo Data

    func makeDemoRows(range: ClosedRange<Int>, reversed: Bool, startLat: Double, startLon: Double, endLat: Double, endLon: Double, maxN: Int, latStep: Double = 0.000005, lonStep: Double = 0.00003) -> [PaddockRow] {
        let numbers: [Int] = reversed ? Array(range.reversed()) : Array(range)
        return numbers.map { n -> PaddockRow in
            let offset = Double(maxN - n)
            let sLat = startLat + offset * latStep
            let sLon = startLon + offset * lonStep
            let eLat = endLat + offset * latStep
            let eLon = endLon + offset * lonStep
            return PaddockRow(number: n,
                              startPoint: CoordinatePoint(latitude: sLat, longitude: sLon),
                              endPoint: CoordinatePoint(latitude: eLat, longitude: eLon))
        }
    }

    func loadDemoData() {
        clearInMemoryState()

        let demoVineyardId = UUID()
        let demoVineyard = Vineyard(
            id: demoVineyardId,
            name: "Demo Vineyard",
            users: [VineyardUser(name: "Demo User", role: .owner)]
        )
        vineyards.append(demoVineyard)
        save(vineyards, key: vineyardsKey)
        selectedVineyardId = demoVineyard.id

        var demoSettings = AppSettings(vineyardId: demoVineyardId)
        demoSettings.weatherStationId = "INEWSOUT1775"
        updateSettings(demoSettings)

        grapeVarieties = GrapeVariety.defaults(for: demoVineyardId)
        var allGrapeVarietiesStore: [GrapeVariety] = loadData(key: grapeVarietiesKey) ?? []
        allGrapeVarietiesStore.removeAll { $0.vineyardId == demoVineyardId }
        allGrapeVarietiesStore.append(contentsOf: grapeVarieties)
        save(allGrapeVarietiesStore, key: grapeVarietiesKey)

        func varietyId(_ name: String) -> UUID {
            grapeVarieties.first { $0.name == name }?.id ?? UUID()
        }
        func alloc(_ name: String) -> [PaddockVarietyAllocation] {
            [PaddockVarietyAllocation(varietyId: varietyId(name), percent: 100)]
        }
        let demoBudburst: Date = {
            var c = DateComponents()
            c.year = 2025; c.month = 10; c.day = 1
            return Calendar.current.date(from: c) ?? Date()
        }()

        let pGruner = Paddock(
            id: UUID(uuidString: "715EE7B8-B5FC-4A4B-A9E9-F8A30F9D62D4")!,
            vineyardId: demoVineyardId,
            name: "Gruner Veltliner",
            polygonPoints: [
                CoordinatePoint(latitude: -33.294464676583765, longitude: 148.95837345152177),
                CoordinatePoint(latitude: -33.29664988172094, longitude: 148.95795121109902),
                CoordinatePoint(latitude: -33.296608195417214, longitude: 148.95752566738577),
                CoordinatePoint(latitude: -33.29438935193399, longitude: 148.95795074805932)
            ],
            rows: makeDemoRows(range: 1...14, reversed: true, startLat: -33.29661, startLon: 148.95754, endLat: -33.29439, endLon: 148.95796, maxN: 14),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: -0.5,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Gruner Veltliner"),
            budburstDate: demoBudburst
        )

        let pShiraz = Paddock(
            id: UUID(uuidString: "486E424E-764E-4E1F-B324-283F33B70BD9")!,
            vineyardId: demoVineyardId,
            name: "Shiraz",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29438360651768, longitude: 148.9579585581722),
                CoordinatePoint(latitude: -33.296603412938985, longitude: 148.95752954988978),
                CoordinatePoint(latitude: -33.29654060083049, longitude: 148.95706240946168),
                CoordinatePoint(latitude: -33.29432258764576, longitude: 148.95748959741272)
            ],
            rows: makeDemoRows(range: 15...30, reversed: true, startLat: -33.29654, startLon: 148.95708, endLat: -33.29432, endLon: 148.95750, maxN: 30, latStep: 0.000004),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Shiraz"),
            budburstDate: demoBudburst
        )

        let pPinotNoir = Paddock(
            id: UUID(uuidString: "A8E82521-257A-49EB-B72E-F892809A2C7B")!,
            vineyardId: demoVineyardId,
            name: "Pinot Noir",
            polygonPoints: [
                CoordinatePoint(latitude: -33.294229405046124, longitude: 148.95446730678736),
                CoordinatePoint(latitude: -33.29495409230544, longitude: 148.95433409128623),
                CoordinatePoint(latitude: -33.29494549825952, longitude: 148.95427642417317),
                CoordinatePoint(latitude: -33.29593531449693, longitude: 148.95408524804103),
                CoordinatePoint(latitude: -33.296163630981184, longitude: 148.9542515439016),
                CoordinatePoint(latitude: -33.296296242739274, longitude: 148.95524552622425),
                CoordinatePoint(latitude: -33.295924088135635, longitude: 148.95531660429367),
                CoordinatePoint(latitude: -33.295625167625566, longitude: 148.95520439929098),
                CoordinatePoint(latitude: -33.29538341491391, longitude: 148.9551856239519),
                CoordinatePoint(latitude: -33.295078777022646, longitude: 148.95513376825343),
                CoordinatePoint(latitude: -33.29486088783918, longitude: 148.95510413436787),
                CoordinatePoint(latitude: -33.2948474831947, longitude: 148.95503745723542),
                CoordinatePoint(latitude: -33.29431946071445, longitude: 148.95513810879112)
            ],
            rows: makeDemoRows(range: 69...108, reversed: true, startLat: -33.29596, startLon: 148.95410, endLat: -33.29423, endLon: 148.95449, maxN: 108),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Pinot Noir"),
            budburstDate: demoBudburst
        )

        let pPrimitivo = Paddock(
            id: UUID(uuidString: "DF0E740B-D65F-4E79-9806-6E3F736B137B")!,
            vineyardId: demoVineyardId,
            name: "Primitivo",
            polygonPoints: [
                CoordinatePoint(latitude: -33.296539731656615, longitude: 148.95706294094194),
                CoordinatePoint(latitude: -33.296509092364175, longitude: 148.95685372863093),
                CoordinatePoint(latitude: -33.294278092587696, longitude: 148.95728159478563),
                CoordinatePoint(latitude: -33.29431668518322, longitude: 148.95749014641655)
            ],
            rows: makeDemoRows(range: 31...37, reversed: true, startLat: -33.29651, startLon: 148.95685, endLat: -33.29428, endLon: 148.95728, maxN: 37),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Primitivo"),
            budburstDate: demoBudburst
        )

        let pCabFranc = Paddock(
            id: UUID(uuidString: "3AB9BF77-3AE1-4C01-A6CC-850DA38B1A5B")!,
            vineyardId: demoVineyardId,
            name: "Cab Franc",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29650967737192, longitude: 148.9568523414743),
                CoordinatePoint(latitude: -33.29647716981803, longitude: 148.95664692895718),
                CoordinatePoint(latitude: -33.294261184967056, longitude: 148.95707340784196),
                CoordinatePoint(latitude: -33.2942874534165, longitude: 148.9572790520895)
            ],
            rows: makeDemoRows(range: 38...44, reversed: true, startLat: -33.29648, startLon: 148.95665, endLat: -33.29426, endLon: 148.95707, maxN: 44),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Cabernet Franc"),
            budburstDate: demoBudburst
        )

        let pSauvBlanc = Paddock(
            id: UUID(uuidString: "DC32EC37-DE50-4620-83B7-CCED1DC65D75")!,
            vineyardId: demoVineyardId,
            name: "Sauv Blanc",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29637534029164, longitude: 148.9559306832998),
                CoordinatePoint(latitude: -33.29588130528306, longitude: 148.95602096414402),
                CoordinatePoint(latitude: -33.29569146808536, longitude: 148.9561713714582),
                CoordinatePoint(latitude: -33.29551093354972, longitude: 148.95621729074338),
                CoordinatePoint(latitude: -33.29548355655761, longitude: 148.95629917438146),
                CoordinatePoint(latitude: -33.295148187706985, longitude: 148.95632718720495),
                CoordinatePoint(latitude: -33.29420277634263, longitude: 148.9565775666412),
                CoordinatePoint(latitude: -33.29421754572732, longitude: 148.9566887560023),
                CoordinatePoint(latitude: -33.29643727927688, longitude: 148.95626231061016)
            ],
            rows: makeDemoRows(range: 58...68, reversed: true, startLat: -33.29644, startLon: 148.95593, endLat: -33.29420, endLon: 148.95626, maxN: 68),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0.5,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Sauvignon Blanc"),
            budburstDate: demoBudburst
        )

        let pMerlot = Paddock(
            id: UUID(uuidString: "43F9BB12-FD3A-45CF-8AE8-22A2D00D688C")!,
            vineyardId: demoVineyardId,
            name: "Merlot",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29425949643701, longitude: 148.95707409583076),
                CoordinatePoint(latitude: -33.2942328331289, longitude: 148.95686330035971),
                CoordinatePoint(latitude: -33.29644934950337, longitude: 148.95644128457215),
                CoordinatePoint(latitude: -33.29647710607891, longitude: 148.95664715973072)
            ],
            rows: makeDemoRows(range: 45...51, reversed: true, startLat: -33.29645, startLon: 148.95644, endLat: -33.29423, endLon: 148.95686, maxN: 51),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Merlot"),
            budburstDate: demoBudburst
        )

        let pPinotGris = Paddock(
            id: UUID(uuidString: "1ABF325F-3EEC-4CAD-912C-12BC2E371928")!,
            vineyardId: demoVineyardId,
            name: "Pinot Gris",
            polygonPoints: [
                CoordinatePoint(latitude: -33.29423498464803, longitude: 148.95686152287013),
                CoordinatePoint(latitude: -33.29421589608211, longitude: 148.95668903200138),
                CoordinatePoint(latitude: -33.2964296646789, longitude: 148.95626403176502),
                CoordinatePoint(latitude: -33.29645708811178, longitude: 148.9564381911035)
            ],
            rows: makeDemoRows(range: 52...57, reversed: false, startLat: -33.29643, startLon: 148.95626, endLat: -33.29422, endLon: 148.95669, maxN: 57),
            rowDirection: 9,
            rowWidth: 2.8,
            rowOffset: 0,
            vineSpacing: 1.0,
            flowPerEmitter: 1.6,
            emitterSpacing: 0.5,
            varietyAllocations: alloc("Pinot Gris / Grigio"),
            budburstDate: demoBudburst
        )

        paddocks = [pShiraz, pPinotNoir, pGruner, pPrimitivo, pCabFranc, pSauvBlanc, pMerlot, pPinotGris]
        var allPaddocks: [Paddock] = loadData(key: paddocksKey) ?? []
        allPaddocks.append(contentsOf: paddocks)
        save(allPaddocks, key: paddocksKey)

        let equip1 = SprayEquipmentItem(vineyardId: demoVineyardId, name: "1500L Croplands QM-420", tankCapacityLitres: 1500)
        let equip2 = SprayEquipmentItem(vineyardId: demoVineyardId, name: "200L Silvan UTE Sprayer", tankCapacityLitres: 200)
        sprayEquipment = [equip1, equip2]
        var allEquip: [SprayEquipmentItem] = loadData(key: sprayEquipmentKey) ?? []
        allEquip.append(contentsOf: sprayEquipment)
        save(allEquip, key: sprayEquipmentKey)

        let tractor1 = Tractor(vineyardId: demoVineyardId, name: "John Deere 5075E", brand: "John Deere", model: "5075E", fuelUsageLPerHour: 8.5)
        let tractor2 = Tractor(vineyardId: demoVineyardId, name: "Kubota M7060", brand: "Kubota", model: "M7060", fuelUsageLPerHour: 7.2)
        tractors = [tractor1, tractor2]
        var allTractors: [Tractor] = loadData(key: tractorsKey) ?? []
        allTractors.append(contentsOf: tractors)
        save(allTractors, key: tractorsKey)

        let fp1 = FuelPurchase(vineyardId: demoVineyardId, volumeLitres: 500, totalCost: 950, date: Calendar.current.date(byAdding: .day, value: -30, to: Date())!)
        let fp2 = FuelPurchase(vineyardId: demoVineyardId, volumeLitres: 300, totalCost: 585, date: Calendar.current.date(byAdding: .day, value: -10, to: Date())!)
        fuelPurchases = [fp1, fp2]
        var allFuel: [FuelPurchase] = loadData(key: fuelPurchasesKey) ?? []
        allFuel.append(contentsOf: fuelPurchases)
        save(allFuel, key: fuelPurchasesKey)

        let mancozebLowRate = ChemicalRate(label: "Low", value: ChemicalUnit.grams.toBase(200), basis: .perHectare)
        let mancozebHighRate = ChemicalRate(label: "High", value: ChemicalUnit.grams.toBase(300), basis: .perHectare)
        let mancozeb = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Mancozeb 750 WG",
            unit: .grams,
            chemicalGroup: "M3 — Dithiocarbamate",
            use: "Downy Mildew preventative",
            manufacturer: "Nufarm",
            activeIngredient: "Mancozeb 750g/kg",
            rates: [mancozebLowRate, mancozebHighRate],
            purchase: ChemicalPurchase(brand: "Nufarm", activeIngredient: "Mancozeb 750g/kg", costDollars: 42, containerSizeML: 10, containerUnit: .kilograms)
        )

        let copperLowRate = ChemicalRate(label: "Low", value: ChemicalUnit.millilitres.toBase(150), basis: .per100Litres)
        let copperHighRate = ChemicalRate(label: "High", value: ChemicalUnit.millilitres.toBase(250), basis: .per100Litres)
        let copperOxychloride = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Copper Oxychloride 500 SC",
            unit: .millilitres,
            chemicalGroup: "M1 — Copper",
            use: "Downy Mildew protectant",
            manufacturer: "BASF",
            activeIngredient: "Copper Oxychloride 500g/L",
            rates: [copperLowRate, copperHighRate],
            purchase: ChemicalPurchase(brand: "BASF", activeIngredient: "Copper Oxychloride 500g/L", costDollars: 85, containerSizeML: 20, containerUnit: .litres)
        )

        let sulphurHaRate = ChemicalRate(label: "Standard", value: ChemicalUnit.kilograms.toBase(3), basis: .perHectare)
        let sulphur = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Wettable Sulphur 800 WG",
            unit: .kilograms,
            chemicalGroup: "M2 — Inorganic (Sulphur)",
            use: "Powdery Mildew preventative",
            manufacturer: "Bayer",
            activeIngredient: "Sulphur 800g/kg",
            rates: [sulphurHaRate],
            purchase: ChemicalPurchase(brand: "Bayer", activeIngredient: "Sulphur 800g/kg", costDollars: 28, containerSizeML: 15, containerUnit: .kilograms)
        )

        let trifloxystrobinRate = ChemicalRate(label: "Standard", value: ChemicalUnit.millilitres.toBase(150), basis: .perHectare)
        let trifloxystrobin = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Flint 500 WG",
            unit: .millilitres,
            chemicalGroup: "11 — Strobilurin",
            use: "Powdery Mildew curative",
            manufacturer: "Bayer",
            activeIngredient: "Trifloxystrobin 500g/kg",
            rates: [trifloxystrobinRate],
            purchase: ChemicalPurchase(brand: "Bayer", activeIngredient: "Trifloxystrobin 500g/kg", costDollars: 195, containerSizeML: 1, containerUnit: .kilograms)
        )

        let phosphonateRate100L = ChemicalRate(label: "Standard", value: ChemicalUnit.millilitres.toBase(500), basis: .per100Litres)
        let phosphonate = SavedChemical(
            vineyardId: demoVineyardId,
            name: "Agri-Fos 600",
            unit: .litres,
            chemicalGroup: "33 — Phosphonate",
            use: "Downy Mildew systemic",
            manufacturer: "AgNova",
            activeIngredient: "Phosphorous Acid 600g/L",
            rates: [phosphonateRate100L],
            purchase: ChemicalPurchase(brand: "AgNova", activeIngredient: "Phosphorous Acid 600g/L", costDollars: 65, containerSizeML: 20, containerUnit: .litres)
        )

        savedChemicals = [mancozeb, copperOxychloride, sulphur, trifloxystrobin, phosphonate]
        var allChemicals: [SavedChemical] = loadData(key: savedChemicalsKey) ?? []
        allChemicals.append(contentsOf: savedChemicals)
        save(allChemicals, key: savedChemicalsKey)

        let cal = Calendar.current
        let now = Date()

        let baseLat = -33.29546
        let baseLon = 148.95751

        func generatePath(startLat: Double, startLon: Double, rows: Int, rowSpacing: Double) -> [CoordinatePoint] {
            var points: [CoordinatePoint] = []
            let rowLengthDeg = 0.002
            let rowSpacingDeg = rowSpacing / 111320.0
            let angleDeg = 9.0
            let angleRad = angleDeg * .pi / 180.0
            let cosA = cos(angleRad)
            let sinA = sin(angleRad)
            let cosLat = cos(startLat * .pi / 180.0)
            for r in 0..<rows {
                let perpLat = Double(r) * rowSpacingDeg * (-sinA)
                let perpLon = Double(r) * rowSpacingDeg * cosA / cosLat
                let rowBaseLat = startLat + perpLat
                let rowBaseLon = startLon + perpLon
                let dLat = rowLengthDeg * cosA
                let dLon = rowLengthDeg * sinA / cosLat
                if r % 2 == 0 {
                    points.append(CoordinatePoint(latitude: rowBaseLat, longitude: rowBaseLon))
                    points.append(CoordinatePoint(latitude: rowBaseLat + dLat, longitude: rowBaseLon + dLon))
                } else {
                    points.append(CoordinatePoint(latitude: rowBaseLat + dLat, longitude: rowBaseLon + dLon))
                    points.append(CoordinatePoint(latitude: rowBaseLat, longitude: rowBaseLon))
                }
            }
            return points
        }

        let trip1Id = UUID()
        let trip1Start = cal.date(byAdding: .day, value: -21, to: now)!
        let trip1End = cal.date(byAdding: .hour, value: 3, to: trip1Start)!
        let trip1Seq = TrackingPattern.sequential.generateSequence(startRow: 15, totalRows: 16)
        let trip1 = Trip(
            id: trip1Id,
            vineyardId: demoVineyardId,
            paddockId: pShiraz.id,
            paddockName: pShiraz.name,
            paddockIds: [pShiraz.id],
            startTime: trip1Start,
            endTime: trip1End,
            currentRowNumber: 30.5,
            nextRowNumber: 31.5,
            pathPoints: generatePath(startLat: -33.29654, startLon: 148.95708, rows: 16, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip1Seq,
            sequenceIndex: trip1Seq.count,
            personName: "Demo User",
            totalDistance: 4200,
            completedPaths: trip1Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip1Start, endTime: cal.date(byAdding: .hour, value: 1, to: trip1Start), pathsCovered: Array(trip1Seq.prefix(6)), startRow: 14.5, endRow: 19.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 1, to: trip1Start)!, endTime: cal.date(byAdding: .hour, value: 2, to: trip1Start), pathsCovered: Array(trip1Seq.dropFirst(6).prefix(5)), startRow: 20.5, endRow: 24.5),
                TankSession(tankNumber: 3, startTime: cal.date(byAdding: .hour, value: 2, to: trip1Start)!, endTime: trip1End, pathsCovered: Array(trip1Seq.suffix(5)), startRow: 25.5, endRow: 30.5)
            ],
            totalTanks: 3
        )

        let trip2Id = UUID()
        let trip2Start = cal.date(byAdding: .day, value: -14, to: now)!
        let trip2End = cal.date(byAdding: .hour, value: 2, to: trip2Start)!
        let trip2Seq = TrackingPattern.everySecondRow.generateSequence(startRow: 1, totalRows: 14)
        let trip2 = Trip(
            id: trip2Id,
            vineyardId: demoVineyardId,
            paddockId: pGruner.id,
            paddockName: pGruner.name,
            paddockIds: [pGruner.id],
            startTime: trip2Start,
            endTime: trip2End,
            currentRowNumber: 14.5,
            nextRowNumber: 15.5,
            pathPoints: generatePath(startLat: -33.29661, startLon: 148.95754, rows: 14, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .everySecondRow,
            rowSequence: trip2Seq,
            sequenceIndex: trip2Seq.count,
            personName: "Demo User",
            totalDistance: 3150,
            completedPaths: trip2Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip2Start, endTime: cal.date(byAdding: .hour, value: 1, to: trip2Start), pathsCovered: Array(trip2Seq.prefix(7)), startRow: 0.5, endRow: 13.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 1, to: trip2Start)!, endTime: trip2End, pathsCovered: Array(trip2Seq.suffix(7)), startRow: 12.5, endRow: 1.5)
            ],
            totalTanks: 2
        )

        let trip3Id = UUID()
        let trip3Start = cal.date(byAdding: .day, value: -7, to: now)!
        let trip3End = cal.date(byAdding: .minute, value: 90, to: trip3Start)!
        let trip3Seq = TrackingPattern.sequential.generateSequence(startRow: 31, totalRows: 7)
        let trip3 = Trip(
            id: trip3Id,
            vineyardId: demoVineyardId,
            paddockId: pPrimitivo.id,
            paddockName: pPrimitivo.name,
            paddockIds: [pPrimitivo.id],
            startTime: trip3Start,
            endTime: trip3End,
            currentRowNumber: 37.5,
            nextRowNumber: 38.5,
            pathPoints: generatePath(startLat: -33.29651, startLon: 148.95685, rows: 7, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip3Seq,
            sequenceIndex: trip3Seq.count,
            personName: "Demo User",
            totalDistance: 2100,
            completedPaths: trip3Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip3Start, endTime: trip3End, pathsCovered: trip3Seq, startRow: 30.5, endRow: 37.5)
            ],
            totalTanks: 1
        )

        let trip4Id = UUID()
        let trip4Start = cal.date(byAdding: .day, value: -3, to: now)!
        let trip4End = cal.date(byAdding: .hour, value: 4, to: trip4Start)!
        let trip4Seq = TrackingPattern.sequential.generateSequence(startRow: 15, totalRows: 16)
        let trip4 = Trip(
            id: trip4Id,
            vineyardId: demoVineyardId,
            paddockId: pShiraz.id,
            paddockName: "\(pShiraz.name), \(pPinotNoir.name)",
            paddockIds: [pShiraz.id, pPinotNoir.id],
            startTime: trip4Start,
            endTime: trip4End,
            currentRowNumber: 30.5,
            nextRowNumber: 31.5,
            pathPoints: generatePath(startLat: -33.29654, startLon: 148.95708, rows: 16, rowSpacing: 2.8),
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: trip4Seq,
            sequenceIndex: trip4Seq.count,
            personName: "Demo User",
            totalDistance: 5600,
            completedPaths: trip4Seq,
            tankSessions: [
                TankSession(tankNumber: 1, startTime: trip4Start, endTime: cal.date(byAdding: .hour, value: 2, to: trip4Start), pathsCovered: Array(trip4Seq.prefix(8)), startRow: 14.5, endRow: 21.5),
                TankSession(tankNumber: 2, startTime: cal.date(byAdding: .hour, value: 2, to: trip4Start)!, endTime: trip4End, pathsCovered: Array(trip4Seq.suffix(8)), startRow: 22.5, endRow: 30.5)
            ],
            totalTanks: 2
        )

        let trip5Id = UUID()
        let trip5 = Trip(
            id: trip5Id,
            vineyardId: demoVineyardId,
            paddockId: pSauvBlanc.id,
            paddockName: pSauvBlanc.name,
            paddockIds: [pSauvBlanc.id],
            startTime: now,
            isActive: false,
            trackingPattern: .sequential,
            rowSequence: TrackingPattern.sequential.generateSequence(startRow: 58, totalRows: 11),
            personName: "Demo User"
        )

        trips = [trip1, trip2, trip3, trip4, trip5]
        var allTrips: [Trip] = loadData(key: tripsKey) ?? []
        allTrips.append(contentsOf: trips)
        save(allTrips, key: tripsKey)

        let mancozebCostPerBase = mancozeb.purchase?.costPerBaseUnit ?? 0
        let copperCostPerBase = copperOxychloride.purchase?.costPerBaseUnit ?? 0
        let sulphurCostPerBase = sulphur.purchase?.costPerBaseUnit ?? 0
        let trifloxyCostPerBase = trifloxystrobin.purchase?.costPerBaseUnit ?? 0
        let phosphonateCostPerBase = phosphonate.purchase?.costPerBaseUnit ?? 0

        let sprayRecord1 = SprayRecord(
            tripId: trip1Id,
            vineyardId: demoVineyardId,
            date: trip1Start,
            startTime: trip1Start,
            endTime: trip1End,
            temperature: 18.5,
            windSpeed: 12.0,
            windDirection: "NW",
            humidity: 65,
            sprayReference: "Downy Mildew Prevention — Spray 1",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(2250), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(2250), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 3, waterVolume: 1000, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(400), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Copper Oxychloride 500 SC", volumePerTank: ChemicalUnit.millilitres.toBase(1500), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: copperCostPerBase, unit: .millilitres)
                ])
            ],
            notes: "Good conditions, light NW breeze. Full coverage on Shiraz block.",
            numberOfFansJets: "6",
            averageSpeed: 5.2,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "2L"
        )

        let sprayRecord2 = SprayRecord(
            tripId: trip2Id,
            vineyardId: demoVineyardId,
            date: trip2Start,
            startTime: trip2Start,
            endTime: trip2End,
            temperature: 22.0,
            windSpeed: 8.5,
            windDirection: "SE",
            humidity: 55,
            sprayReference: "Powdery Mildew Control — Spray 1",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 700, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(4.5), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms),
                    SprayChemical(name: "Flint 500 WG", volumePerTank: ChemicalUnit.millilitres.toBase(321), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: trifloxyCostPerBase, unit: .millilitres)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1200, sprayRatePerHa: 700, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(3.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms),
                    SprayChemical(name: "Flint 500 WG", volumePerTank: ChemicalUnit.millilitres.toBase(257), ratePerHa: ChemicalUnit.millilitres.toBase(150), costPerUnit: trifloxyCostPerBase, unit: .millilitres)
                ])
            ],
            notes: "Warm day, applied early morning on Gruner Veltliner.",
            numberOfFansJets: "6",
            averageSpeed: 4.8,
            equipmentType: "1500L Croplands QM-420",
            tractor: "Kubota M7060",
            tractorGear: "2L"
        )

        let sprayRecord3 = SprayRecord(
            tripId: trip3Id,
            vineyardId: demoVineyardId,
            date: trip3Start,
            startTime: trip3Start,
            endTime: trip3End,
            temperature: 16.0,
            windSpeed: 5.0,
            windDirection: "N",
            humidity: 72,
            sprayReference: "Downy Mildew Systemic — Spray 2",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 800, sprayRatePerHa: 600, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Agri-Fos 600", volumePerTank: ChemicalUnit.millilitres.toBase(4000), ratePerHa: ChemicalUnit.millilitres.toBase(500), costPerUnit: phosphonateCostPerBase, unit: .litres)
                ])
            ],
            notes: "Primitivo block, single tank coverage. Cool conditions.",
            numberOfFansJets: "4",
            averageSpeed: 4.5,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "1H"
        )

        let sprayRecord4 = SprayRecord(
            tripId: trip4Id,
            vineyardId: demoVineyardId,
            date: trip4Start,
            startTime: trip4Start,
            endTime: trip4End,
            temperature: 20.0,
            windSpeed: 10.0,
            windDirection: "SW",
            humidity: 60,
            sprayReference: "Season Protection — Spray 3",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(5.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ]),
                SprayTank(tankNumber: 2, waterVolume: 1500, sprayRatePerHa: 800, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Mancozeb 750 WG", volumePerTank: ChemicalUnit.grams.toBase(600), ratePerHa: ChemicalUnit.grams.toBase(200), costPerUnit: mancozebCostPerBase, unit: .grams),
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(5.6), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ])
            ],
            notes: "Multi-block spray covering Shiraz and Pinot Noir. Moderate SW wind.",
            numberOfFansJets: "6",
            averageSpeed: 5.0,
            equipmentType: "1500L Croplands QM-420",
            tractor: "John Deere 5075E",
            tractorGear: "2L"
        )

        let sprayRecord5 = SprayRecord(
            tripId: trip5Id,
            vineyardId: demoVineyardId,
            date: now,
            startTime: now,
            sprayReference: "Powdery Mildew Prevention — Spray 2",
            tanks: [
                SprayTank(tankNumber: 1, waterVolume: 800, sprayRatePerHa: 600, concentrationFactor: 1.0, chemicals: [
                    SprayChemical(name: "Wettable Sulphur 800 WG", volumePerTank: ChemicalUnit.kilograms.toBase(3), ratePerHa: ChemicalUnit.kilograms.toBase(3), costPerUnit: sulphurCostPerBase, unit: .kilograms)
                ])
            ],
            equipmentType: "1500L Croplands QM-420",
            tractor: "Kubota M7060",
            tractorGear: "2L"
        )

        sprayRecords = [sprayRecord1, sprayRecord2, sprayRecord3, sprayRecord4, sprayRecord5]
        var allSprayRecords: [SprayRecord] = loadData(key: sprayRecordsKey) ?? []
        allSprayRecords.append(contentsOf: sprayRecords)
        save(allSprayRecords, key: sprayRecordsKey)

        // MARK: Demo Pins

        let demoPins: [VinePin] = [
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29520, longitude: 148.95770,
                heading: 9, buttonName: "Irrigation", buttonColor: "blue",
                side: .left, mode: .repairs,
                paddockId: pShiraz.id, rowNumber: 18,
                timestamp: cal.date(byAdding: .day, value: -20, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip1Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29485, longitude: 148.95778,
                heading: 9, buttonName: "Broken Post", buttonColor: "brown",
                side: .right, mode: .repairs,
                paddockId: pShiraz.id, rowNumber: 22,
                timestamp: cal.date(byAdding: .day, value: -20, to: now)!,
                createdBy: "Demo User", isCompleted: true,
                completedBy: "Demo User",
                completedAt: cal.date(byAdding: .day, value: -15, to: now)!,
                tripId: trip1Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29555, longitude: 148.95762,
                heading: 9, buttonName: "Vine Issue", buttonColor: "green",
                side: .left, mode: .repairs,
                paddockId: pShiraz.id, rowNumber: 16,
                timestamp: cal.date(byAdding: .day, value: -19, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip1Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29580, longitude: 148.95810,
                heading: 9, buttonName: "Irrigation", buttonColor: "blue",
                side: .right, mode: .repairs,
                paddockId: pGruner.id, rowNumber: 5,
                timestamp: cal.date(byAdding: .day, value: -13, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip2Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29510, longitude: 148.95820,
                heading: 9, buttonName: "Broken Post", buttonColor: "brown",
                side: .left, mode: .repairs,
                paddockId: pGruner.id, rowNumber: 9,
                timestamp: cal.date(byAdding: .day, value: -13, to: now)!,
                createdBy: "Demo User", isCompleted: true,
                completedBy: "Demo User",
                completedAt: cal.date(byAdding: .day, value: -8, to: now)!,
                tripId: trip2Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29470, longitude: 148.95828,
                heading: 9, buttonName: "Other", buttonColor: "red",
                side: .right, mode: .repairs,
                paddockId: pGruner.id, rowNumber: 12,
                timestamp: cal.date(byAdding: .day, value: -12, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip2Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29540, longitude: 148.95700,
                heading: 9, buttonName: "Irrigation", buttonColor: "blue",
                side: .left, mode: .repairs,
                paddockId: pPrimitivo.id, rowNumber: 33,
                timestamp: cal.date(byAdding: .day, value: -6, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip3Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29500, longitude: 148.95710,
                heading: 9, buttonName: "Broken Post", buttonColor: "brown",
                side: .right, mode: .repairs,
                paddockId: pPrimitivo.id, rowNumber: 35,
                timestamp: cal.date(byAdding: .day, value: -6, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip3Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29530, longitude: 148.95440,
                heading: 9, buttonName: "Vine Issue", buttonColor: "green",
                side: .left, mode: .repairs,
                paddockId: pPinotNoir.id, rowNumber: 75,
                timestamp: cal.date(byAdding: .day, value: -2, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip4Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29490, longitude: 148.95450,
                heading: 9, buttonName: "Irrigation", buttonColor: "blue",
                side: .right, mode: .repairs,
                paddockId: pPinotNoir.id, rowNumber: 80,
                timestamp: cal.date(byAdding: .day, value: -2, to: now)!,
                createdBy: "Demo User", isCompleted: true,
                completedBy: "Demo User",
                completedAt: cal.date(byAdding: .day, value: -1, to: now)!,
                tripId: trip4Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29460, longitude: 148.95460,
                heading: 9, buttonName: "Other", buttonColor: "red",
                side: .left, mode: .repairs,
                paddockId: pPinotNoir.id, rowNumber: 85,
                timestamp: cal.date(byAdding: .day, value: -2, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip4Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29560, longitude: 148.95670,
                heading: 9, buttonName: "Broken Post", buttonColor: "brown",
                side: .right, mode: .repairs,
                paddockId: pCabFranc.id, rowNumber: 40,
                timestamp: cal.date(byAdding: .day, value: -4, to: now)!,
                createdBy: "Demo User", isCompleted: false
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29530, longitude: 148.95650,
                heading: 9, buttonName: "Irrigation", buttonColor: "blue",
                side: .left, mode: .repairs,
                paddockId: pMerlot.id, rowNumber: 48,
                timestamp: cal.date(byAdding: .day, value: -5, to: now)!,
                createdBy: "Demo User", isCompleted: true,
                completedBy: "Demo User",
                completedAt: cal.date(byAdding: .day, value: -3, to: now)!
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29550, longitude: 148.95610,
                heading: 9, buttonName: "Vine Issue", buttonColor: "green",
                side: .right, mode: .repairs,
                paddockId: pSauvBlanc.id, rowNumber: 62,
                timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
                createdBy: "Demo User", isCompleted: false
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29515, longitude: 148.95775,
                heading: 9, buttonName: "Growth Stage", buttonColor: "darkgreen",
                side: .left, mode: .growth,
                paddockId: pShiraz.id, rowNumber: 20,
                timestamp: cal.date(byAdding: .day, value: -18, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip1Id, growthStageCode: "EL15"
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29480, longitude: 148.95785,
                heading: 9, buttonName: "Powdery", buttonColor: "gray",
                side: .right, mode: .growth,
                paddockId: pShiraz.id, rowNumber: 24,
                timestamp: cal.date(byAdding: .day, value: -17, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip1Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29550, longitude: 148.95815,
                heading: 9, buttonName: "Downy", buttonColor: "yellow",
                side: .left, mode: .growth,
                paddockId: pGruner.id, rowNumber: 3,
                timestamp: cal.date(byAdding: .day, value: -12, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip2Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29500, longitude: 148.95825,
                heading: 9, buttonName: "Growth Stage", buttonColor: "darkgreen",
                side: .right, mode: .growth,
                paddockId: pGruner.id, rowNumber: 7,
                timestamp: cal.date(byAdding: .day, value: -11, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip2Id, growthStageCode: "EL19"
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29525, longitude: 148.95435,
                heading: 9, buttonName: "Blackberries", buttonColor: "red",
                side: .left, mode: .growth,
                paddockId: pPinotNoir.id, rowNumber: 78,
                timestamp: cal.date(byAdding: .day, value: -2, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip4Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29470, longitude: 148.95455,
                heading: 9, buttonName: "Growth Stage", buttonColor: "darkgreen",
                side: .right, mode: .growth,
                paddockId: pPinotNoir.id, rowNumber: 88,
                timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip4Id, growthStageCode: "EL23"
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29545, longitude: 148.95695,
                heading: 9, buttonName: "Powdery", buttonColor: "gray",
                side: .left, mode: .growth,
                paddockId: pPrimitivo.id, rowNumber: 34,
                timestamp: cal.date(byAdding: .day, value: -5, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                tripId: trip3Id
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29520, longitude: 148.95640,
                heading: 9, buttonName: "Downy", buttonColor: "yellow",
                side: .right, mode: .growth,
                paddockId: pPinotGris.id, rowNumber: 54,
                timestamp: cal.date(byAdding: .day, value: -3, to: now)!,
                createdBy: "Demo User", isCompleted: false
            ),
            VinePin(
                vineyardId: demoVineyardId,
                latitude: -33.29570, longitude: 148.95615,
                heading: 9, buttonName: "Growth Stage", buttonColor: "darkgreen",
                side: .left, mode: .growth,
                paddockId: pSauvBlanc.id, rowNumber: 60,
                timestamp: cal.date(byAdding: .day, value: -1, to: now)!,
                createdBy: "Demo User", isCompleted: false,
                growthStageCode: "EL27"
            ),
        ]

        pins = demoPins
        var allPins: [VinePin] = loadData(key: pinsKey) ?? []
        allPins.append(contentsOf: demoPins)
        save(allPins, key: pinsKey)
    }
}
