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
        
        return OCKCarePlanStore(persistenceDirectoryURL: url)
    }()
    
    let activityStartDate = DateComponents(year: 2016, month: 1, day: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        addActivities()
        
        let careCard = OCKCareCardViewController(carePlanStore: carePlanStore)
        careCard.title = "Care"
        let symptomTracker = OCKSymptomTrackerViewController(carePlanStore: carePlanStore)
        symptomTracker.title = "Measurements"
        symptomTracker.delegate = self
        
        viewControllers = [
            UINavigationController(rootViewController: careCard),
            UINavigationController(rootViewController: symptomTracker)
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
