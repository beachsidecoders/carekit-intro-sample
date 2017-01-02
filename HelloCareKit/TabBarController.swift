/*
 Copyright (c) 2017 Beachside Coders
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import CareKit

class TabBarController: UITabBarController {
    
    lazy var carePlanStore: OCKCarePlanStore = {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let url = urls[0].appendingPathComponent("carePlanStore")
        
        if !fileManager.fileExists(atPath: url.path) {
            try! fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        
        let store = OCKCarePlanStore(persistenceDirectoryURL: url)
        store.delegate = self
        return store
    }()
    
    let activityStartDate = DateComponents(year: 2016, month: 1, day: 1)
    let calendar = Calendar(identifier: .gregorian)
    lazy var monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()
    var today: Date {
        return Date()
    }
    
    var insights: OCKInsightsViewController!
    var insightItems = [OCKInsightItem]() {
        didSet {
            insights.items = insightItems
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addActivities()
        
        let careCard = OCKCareCardViewController(carePlanStore: carePlanStore)
        careCard.title = "Care"
        let symptomTracker = OCKSymptomTrackerViewController(carePlanStore: carePlanStore)
        symptomTracker.title = "Measurements"
        symptomTracker.delegate = self
        insights = OCKInsightsViewController(insightItems: insightItems)
        insights.title = "Insights"
        updateInsights()
        
        viewControllers = [
            UINavigationController(rootViewController: careCard),
            UINavigationController(rootViewController: symptomTracker),
            UINavigationController(rootViewController: insights)
        ]
    }
    
    func addActivities() {
        carePlanStore.activities { [unowned self] (_, activities, error) in
            if let error = error {
                print(error.localizedDescription)
            }
            guard activities.count == 0 else { return }
            
            for activity in self.interventions() + self.assessments() {
                self.carePlanStore.add(activity) { (_, error) in
                    guard let error = error else { return }
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    func interventions() -> [OCKCarePlanActivity] {
        let waterSchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 8)
        let waterIntervention = OCKCarePlanActivity.intervention(withIdentifier: "water", groupIdentifier: nil, title: "Water", text: "Number of glasses", tintColor: .blue, instructions: nil, imageURL: nil, schedule: waterSchedule, userInfo: nil)
        
        let exerciseSchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 1, daysToSkip: 1, endDate: nil)
        let exerciseIntervention = OCKCarePlanActivity.intervention(withIdentifier: "exercise", groupIdentifier: nil, title: "Exercise", text: "30 min", tintColor: .orange, instructions: nil, imageURL: nil, schedule: exerciseSchedule, userInfo: nil)
        
        return [waterIntervention, exerciseIntervention]
    }
    
    func assessments() -> [OCKCarePlanActivity] {
        let oncePerDaySchedule = OCKCareSchedule.dailySchedule(withStartDate: activityStartDate, occurrencesPerDay: 1)
        
        let sleepAssessment = OCKCarePlanActivity.assessment(withIdentifier: "sleep", groupIdentifier: nil, title: "Sleep", text: "How many hours did you sleep last night?", tintColor: .purple, resultResettable: true, schedule: oncePerDaySchedule, userInfo: nil)
        let weightAssessment = OCKCarePlanActivity.assessment(withIdentifier: "weight", groupIdentifier: nil, title: "Weight", text: "How much do you weigh?", tintColor: .brown, resultResettable: true, schedule: oncePerDaySchedule, userInfo: nil)
        
        return [sleepAssessment, weightAssessment]
    }
    
    func updateInsights() {
        self.insightItems = []
        
        var sleep = [DateComponents: Int]()
        var interventionCompletion = [DateComponents: Int]()
        
        let activitiesDispatchGroup = DispatchGroup()
        
        activitiesDispatchGroup.enter()
        fetchSleep { sleepDict in
            sleep = sleepDict
            activitiesDispatchGroup.leave()
        }
        
        activitiesDispatchGroup.enter()
        fetchInterventionCompletion { interventionCompletionDict in
            interventionCompletion = interventionCompletionDict
            activitiesDispatchGroup.leave()
        }
        
        activitiesDispatchGroup.notify(queue: .main) {
            if let sleepMessage = self.sleepMessage(sleep: sleep) {
                self.insightItems.append(sleepMessage)
            }
            self.insightItems.append(self.interventionBarChart(interventionCompletion: interventionCompletion, sleep: sleep))
        }
    }
    
    func fetchSleep(completion: @escaping ([DateComponents: Int]) -> ()) {
        var sleep = [DateComponents: Int]()
        
        let sleepStartDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -7), to: today)!)
        let sleepEndDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -1), to: today)!)
        
        carePlanStore.activity(forIdentifier: "sleep") { [unowned self] (_, activity, error) in
            if let error = error {
                print(error.localizedDescription)
            }
            guard let sleepAssessment = activity else { return }
            self.carePlanStore.enumerateEvents(of: sleepAssessment, startDate: sleepStartDate, endDate: sleepEndDate, handler: { (event, _) in
                guard let event = event else { return }
                if let result = event.result {
                    sleep[event.date] = Int(result.valueString)!
                } else {
                    sleep[event.date] = 0
                }
            }, completion: { (_, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
                completion(sleep)
            })
        }
    }
    
    func fetchInterventionCompletion(completion: @escaping ([DateComponents: Int]) -> ()) {
        var interventionCompletion = [DateComponents: Int]()
        
        let interventionStartDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -7), to: today)!)
        let interventionEndDate = calendar.dateComponents([.year, .month, .day], from: calendar.date(byAdding: DateComponents(day: -1), to: today)!)
        
        carePlanStore.dailyCompletionStatus(with: .intervention, startDate: interventionStartDate, endDate: interventionEndDate, handler: { (date, completed, total) in
            interventionCompletion[date] = lround((Double(completed) / Double(total)) * 100)
        }, completion: { (_, error) in
            if let error = error {
                print(error.localizedDescription)
            }
            completion(interventionCompletion)
        })
    }
    
    func sleepMessage(sleep: [DateComponents: Int]) -> OCKMessageItem? {
        let sleepAverage = Double(sleep.values.reduce(0) { $0 + $1 }) / Double(sleep.count)
        let sleepAverageInt = lround(sleepAverage)
        
        if sleepAverage < 6 {
            let averageAlert = OCKMessageItem(title: "Sleep More", text: "You only got an average of \(sleepAverageInt) hours of sleep this week.", tintColor: .purple, messageType: .alert)
            return averageAlert
        } else if sleep.values.max()! - sleep.values.min()! >= 3 {
            let consistentAlert = OCKMessageItem(title: "Be More Consistent", text: "Try to get the same amount of sleep each night to stay healthy.", tintColor: .purple, messageType: .alert)
            return consistentAlert
        } else if sleepAverage > 7.5 {
            let averageTip = OCKMessageItem(title: "Maintain Sleep Habits", text: "Nice job getting a lot of sleep last week. Keep it up!", tintColor: .purple, messageType: .tip)
            return averageTip
        }
        return nil
    }
    
    func interventionBarChart(interventionCompletion: [DateComponents: Int], sleep: [DateComponents: Int]) -> OCKBarChart {
        let sortedDates = interventionCompletion.keys.sorted() {
            calendar.dateComponents([.second], from: $0, to: $1).second! > 0
        }
        let formattedDates = sortedDates.map {
            monthDayFormatter.string(from: calendar.date(from: $0)!)
        }
        
        let interventionValues = sortedDates.map { interventionCompletion[$0]! }
        let interventionSeries = OCKBarSeries(title: "Care Completion", values: interventionValues as [NSNumber], valueLabels: interventionValues.map { "\($0)%" }, tintColor: .red)
        
        let sleepNumbers = sortedDates.map { sleep[$0]! }
        let sleepValues: [Double]
        if sleep.values.max()! > 0 {
            let singleHourWidth = 100.0 / Double(sleep.values.max()!)
            sleepValues = sleepNumbers.map { singleHourWidth * Double($0) }
        } else {
            sleepValues = sleepNumbers.map { _ in 0 }
        }
        let sleepSeries = OCKBarSeries(title: "Sleep", values: sleepValues as [NSNumber], valueLabels: sleepNumbers.map { "\($0)" }, tintColor: .purple)
        
        let interventionBarChart = OCKBarChart(title: "Care Completion to Sleep", text: "See how completing your care plan affects how much you sleep.", tintColor: nil, axisTitles: formattedDates, axisSubtitles: nil, dataSeries: [interventionSeries, sleepSeries], minimumScaleRangeValue: 0, maximumScaleRangeValue: 100)
        return interventionBarChart
    }

}

extension TabBarController: OCKSymptomTrackerViewControllerDelegate {
    
    func symptomTrackerViewController(_ viewController: OCKSymptomTrackerViewController, didSelectRowWithAssessmentEvent assessmentEvent: OCKCarePlanEvent) {
        let alert: UIAlertController
        
        if assessmentEvent.activity.identifier == "sleep" {
            alert = sleepAlert(event: assessmentEvent)
        } else if assessmentEvent.activity.identifier == "weight" {
            alert = weightAlert(event: assessmentEvent)
        } else {
            return
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alert.addAction(cancelAction)
        
        present(alert, animated: true, completion: nil)
    }
    
    func sleepAlert(event: OCKCarePlanEvent) -> UIAlertController {
        let alert = UIAlertController(title: "Sleep", message: "How many hours did you sleep last night?", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
        }
        
        let doneAction = UIAlertAction(title: "Done", style: .default) { [unowned self] _ in
            let sleepField = alert.textFields![0]
            let result = OCKCarePlanEventResult(valueString: sleepField.text!, unitString: "hours", userInfo: nil)
            self.carePlanStore.update(event, with: result, state: .completed) { (_, _, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        }
        alert.addAction(doneAction)
        
        return alert
    }
    
    func weightAlert(event: OCKCarePlanEvent) -> UIAlertController {
        let alert = UIAlertController(title: "Weight", message: "How much do you weigh (in kilograms)?", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
        }
        let doneAction = UIAlertAction(title: "Done", style: .default) { [unowned self] _ in
            let weightField = alert.textFields![0]
            let result = OCKCarePlanEventResult(valueString: weightField.text!, unitString: "kg", userInfo: nil)
            self.carePlanStore.update(event, with: result, state: .completed) { (_, _, error) in
                if let error = error {
                    print(error.localizedDescription)
                }
            }
        }
        alert.addAction(doneAction)
        
        return alert
    }
    
}

extension TabBarController: OCKCarePlanStoreDelegate {
    
    func carePlanStore(_ store: OCKCarePlanStore, didReceiveUpdateOf event: OCKCarePlanEvent) {
        updateInsights()
    }
    
}
