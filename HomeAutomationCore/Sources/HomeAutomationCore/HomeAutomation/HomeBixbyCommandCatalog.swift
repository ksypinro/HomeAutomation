import Foundation

public struct HomeBixbyVoiceCommand: Sendable, Hashable, Codable, Identifiable {
    public let capability: String
    public let action: String
    public let enumeration: String?
    public let method: String
    public let accessLevel: String
    public let hint: String

    public var id: String {
        [capability, action, enumeration ?? "none", hint].joined(separator: "|")
    }

    public var capabilityAction: String {
        if let enumeration {
            return "\(capability).\(action).\(enumeration)"
        }
        return "\(capability).\(action)"
    }
}

public enum HomeBixbyCommandCatalog {
    private struct SourceCommand: Decodable {
        let c: String
        let a: String
        let e: String?
        let m: String
        let x: String
        let h: String
    }

    public static let sourceURL = "https://bixbydevelopers.com/dev/docs/bhs-reference/voice-intents"
    public static let capabilitySourceURL = "https://bixbydevelopers.com/dev/docs/bhs-reference/capabilities"
    public static let sourceCommandCount = 456
    public static let sourceCapabilityCount = 149

    private static let sourceJSON = #"""
[{"c":"abnormalOperation","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the tamper alert status of the #{device}"},{"c":"acceleration","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the acceleration of the #{device}"},{"c":"accessibility","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off accessibility on the #{device}"},{"c":"accessibility","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on accessibility on the #{device}"},{"c":"activity","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the activity status of the #{device}"},{"c":"airConditionerLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the air conditioner light of the #{device}"},{"c":"airConditionerLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light of the #{device}"},{"c":"airConditioningMode","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the mode of the #{device}"},{"c":"airConditioningMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the #{device} mode to #{predefinedAirConditioningMode}"},{"c":"airPurifierLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light of the #{device}"},{"c":"airPurifierLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light of the #{device}"},{"c":"airQuality","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the air quality of the #{device}"},{"c":"alarm","a":"setMode","e":null,"m":"POST","x":"PUBLIC","h":"Set the alarm to #{predefinedAlarmMode} mode on the #{device}"},{"c":"alarm","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off the alarm on the #{device}"},{"c":"alarm","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the alarm on the #{device}"},{"c":"ambientMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the ambient mode on the #{device}"},{"c":"ambientMode","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the ambient mode on the #{device}"},{"c":"application","a":"exit","e":null,"m":"POST","x":"INTERNAL","h":"Close the #{predefinedAppName} on the #{device}"},{"c":"application","a":"launch","e":null,"m":"POST","x":"INTERNAL","h":"Launch #{appname} on the #{device}"},{"c":"application","a":"searchIn","e":null,"m":"POST","x":"INTERNAL","h":"Search for #{title} in #{appname} on the #{device}"},{"c":"atmosphericPressure","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the atmospheric pressure of the #{device}"},{"c":"audioStream","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the audio stream on the #{device}"},{"c":"audioStream","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the audio stream on the #{device}"},{"c":"autoDoorOpen","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off auto welcome door on the #{device}"},{"c":"autoDoorOpen","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on auto welcome door on the #{device}"},{"c":"autoEmptyMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off auto empty on the #{device}"},{"c":"autoEmptyMode","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on auto empty on the #{device}"},{"c":"automation","a":"show","e":null,"m":"GET","x":"HIDDEN","h":"Show me the automation list"},{"c":"backlight","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the backlight of the #{device}"},{"c":"backlight","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Increase the backlight of the #{device}"},{"c":"battery","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the battery level of the #{device}"},{"c":"beepControl","a":"beep","e":null,"m":"POST","x":"INTERNAL","h":"Enable the beeping sound on the #{device}"},{"c":"bluetoothConnectedDevice","a":"list","e":null,"m":"GET","x":"INTERNAL","h":"Show my connected devices"},{"c":"bmi","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the BMI of the #{device}"},{"c":"brightness","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the brightness of the #{device} [by #{brightnessDelta}]"},{"c":"brightness","a":"decreasePartial","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the brightness of the #{device} by a little bit"},{"c":"brightness","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the brightness of the #{device}"},{"c":"brightness","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Increase the brightness of the #{device} [by #{brightnessDelta}]"},{"c":"brightness","a":"increasePartial","e":null,"m":"POST","x":"PUBLIC","h":"Increase the brightness of the #{device} by a little"},{"c":"brightness","a":"setMax","e":null,"m":"POST","x":"INTERNAL","h":"Set the brightness of the #{device} to maximum"},{"c":"brightness","a":"setMin","e":null,"m":"POST","x":"INTERNAL","h":"Set the brightness of the #{device} to minimum"},{"c":"brightness","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the brightness of the #{device} to #{brightness}"},{"c":"browser","a":"launch","e":null,"m":"POST","x":"INTERNAL","h":"Open #{webSite} in the browser"},{"c":"browser","a":"searchIn","e":null,"m":"POST","x":"INTERNAL","h":"Search for #{keyword} in the browser"},{"c":"button","a":"press","e":null,"m":"POST","x":"INTERNAL","h":"Press the #{predefinedButton} on the #{device}"},{"c":"bypassState","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the bypass status of the #{device}"},{"c":"cabinetLighting","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light on the #{device}"},{"c":"cabinetLighting","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light on the #{device}"},{"c":"camera","a":"show","e":null,"m":"POST","x":"PUBLIC","h":"Show me the #{device}"},{"c":"captions","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the captions on the #{device}"},{"c":"captions","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the captions on the #{device}"},{"c":"carbonDioxideLevel","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the carbon dioxide level of the #{device}"},{"c":"carbonMonoxideDetection","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the carbon monoxide detection status of the #{device}"},{"c":"carbonMonoxideLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the carbon monoxide level of the #{device}"},{"c":"chairPosition","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the #{device} to #{predefinedChairPosition}"},{"c":"channel","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the channel on the #{device} [by #{channelNumberDelta}]"},{"c":"channel","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"What channel is the #{device} on?"},{"c":"channel","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the channel on the #{device} [by #{channelNumberDelta}]"},{"c":"channel","a":"setByName","e":null,"m":"POST","x":"PUBLIC","h":"Set the channel to #{channelName} on the #{device}"},{"c":"channel","a":"setByNumber","e":null,"m":"POST","x":"PUBLIC","h":"Go to channel #{channelNumber} on the #{device}"},{"c":"channel","a":"setByProgram","e":null,"m":"POST","x":"PUBLIC","h":"Show me #{programName} on the #{device}"},{"c":"channel","a":"setPrevious","e":null,"m":"POST","x":"PUBLIC","h":"Set the previous channel on the #{device}"},{"c":"charger","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"What is the charging status of the #{device}?"},{"c":"chargerLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the lamp on the #{device}"},{"c":"chargerLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the lamp on the #{device}"},{"c":"childLock","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the child lock on the #{device}"},{"c":"childLock","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the child lock on the #{device}"},{"c":"chime","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the #{device} chime"},{"c":"chime","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the #{device} chime"},{"c":"cleaning","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the #{device}"},{"c":"cleaning","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the cleaning status of the #{device}"},{"c":"cleaning","a":"pause","e":null,"m":"POST","x":"INTERNAL","h":"Pause cleaning with the #{device}"},{"c":"cleaning","a":"setMode","e":null,"m":"POST","x":"PUBLIC","h":"Set the cleaning mode of the #{device} to #{predefinedCleaningMode}"},{"c":"cleaning","a":"start","e":null,"m":"POST","x":"INTERNAL","h":"Start cleaning with the #{device} [near #{rvcObjects}] [in #{rvcLocations}]"},{"c":"cleaning","a":"stop","e":null,"m":"POST","x":"PUBLIC","h":"Stop cleaning with the #{device}"},{"c":"cleaningMethod","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set cleaning method to #{predefinedCleaningMethod} with the #{device}"},{"c":"cleaningOption","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the cleaining option of #{rvcLocation} #{device}"},{"c":"cleaningOption","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the cleaning option of #{rvcLocation} #{device}"},{"c":"colorControl","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the color of the #{device} to #{predefinedColorName}"},{"c":"colorInversion","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off color inversion on the #{device}"},{"c":"colorInversion","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on color inversion on the #{device}"},{"c":"colorMode","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"What is the color mode of the #{device}?"},{"c":"colorMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Change the #{device} color to #{predefinedColorMode}"},{"c":"colorTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the color temperature of the #{device}"},{"c":"colorTemperature","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the #{device} color temperature to #{colorTemperature}"},{"c":"colorTemperatureMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Change the #{device} color temperature to #{predefinedColorTemperatureMode}"},{"c":"condition","a":"climate","e":null,"m":"POST","x":"HIDDEN","h":"#{climate}"},{"c":"condition","a":"fineDustLevel","e":null,"m":"POST","x":"HIDDEN","h":"If the fine dust is #{fineDustLevel} #{fineDustNumber}"},{"c":"condition","a":"fineDustState","e":null,"m":"POST","x":"HIDDEN","h":"when the fine dust state is #{fineDustState}"},{"c":"condition","a":"outdoorHumidity","e":null,"m":"POST","x":"HIDDEN","h":"If the humidity is #{outdoorHumidityLevel} #{outdoorHumidityNumber}%"},{"c":"condition","a":"outdoorTemperature","e":null,"m":"POST","x":"HIDDEN","h":"Outside temperature is #{outdoorTemperatureLevel} #{outdoorTemperatureNumber} degrees"},{"c":"condition","a":"presenceIn","e":null,"m":"POST","x":"HIDDEN","h":"When i get #{presenceLocation}"},{"c":"condition","a":"presenceOut","e":null,"m":"POST","x":"HIDDEN","h":"When i leave #{presenceLocation}"},{"c":"condition","a":"scheduleAfter","e":null,"m":"POST","x":"HIDDEN","h":"in #{timeAfterExpression}"},{"c":"condition","a":"scheduleOnce","e":null,"m":"POST","x":"HIDDEN","h":"at #{timeExpression}"},{"c":"condition","a":"scheduleRepeat","e":null,"m":"POST","x":"HIDDEN","h":"#{recurrence} at #{timeExpression} #{meridiem}"},{"c":"condition","a":"sunrise","e":null,"m":"POST","x":"HIDDEN","h":"When the sun comes up"},{"c":"condition","a":"sunset","e":null,"m":"POST","x":"HIDDEN","h":"When the sun sets"},{"c":"condition","a":"ultrafineDustLevel","e":null,"m":"POST","x":"HIDDEN","h":"Ultrafine dust is #{ultrafineDustLevel} #{ultrafineDustNumber}"},{"c":"condition","a":"ultrafineDustState","e":null,"m":"POST","x":"HIDDEN","h":"When ultrafine dust is #{ultrafineDustState}"},{"c":"consumableState","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the consumable status of the #{device}"},{"c":"contactSensor","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the contact status of the #{device}"},{"c":"content","a":"getStatus","e":null,"m":"POST","x":"INTERNAL","h":"Show me the inside of the #{device}"},{"c":"continuity","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"getStatus continuity on #{device}"},{"c":"cooking","a":"cancel","e":null,"m":"POST","x":"PUBLIC","h":"Cancel cooking in the #{device}"},{"c":"cooking","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the #{device}"},{"c":"cooking","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of cooking in the [#{predefinedCompartment}] #{device}"},{"c":"cooking","a":"pause","e":null,"m":"POST","x":"INTERNAL","h":"Pause the #{device}"},{"c":"cooking","a":"setCourse","e":null,"m":"POST","x":"INTERNAL","h":"Set the cooking course of the #{device} to #{mode}"},{"c":"cooking","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start cooking in the #{device}"},{"c":"cooking","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"Start the #{device} [on #{mode}] [for #{cookingTimer}] [at #{cookingTemperature}]"},{"c":"cookingTemperature","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the temperature of the #{device} [by #{cookingTemperatureDelta}]"},{"c":"cookingTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the temperature of the #{device}"},{"c":"cookingTemperature","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the cooking temperature of #{device} [by #{cookingTemperatureDelta}]"},{"c":"cookingTemperature","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the cooking temperature of the #{device} to #{cookingTemperature}"},{"c":"cookingTimer","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the cooking time on the #{device} to #{cookingTimer}"},{"c":"cookingTimer","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaning time on the #{device}"},{"c":"cookingTimer","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Increase the cooking time on the #{device} to #{cookingTimer}"},{"c":"cookingTimer","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the cooking time on the #{device} to #{cookingTimer}"},{"c":"coolMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off cool mode on the #{device}"},{"c":"coolMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on cool mode on the #{device}"},{"c":"coolingTemperature","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the cooling temperature of the #{device} [by #{coolingTemperatureDelta}]"},{"c":"coolingTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the cooling temperature of the #{device}"},{"c":"coolingTemperature","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the cooling temperature of the #{device} [by #{coolingTemperatureDelta}]"},{"c":"coolingTemperature","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the cooling temperature of the #{device} to #{coolingTemperature} [#{predefinedCoolingTemperatureUnit}]"},{"c":"cubeRefrigeratorLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light on the #{device}"},{"c":"cubeRefrigeratorLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light in the #{device}"},{"c":"currentTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the current temperature of the #{device}"},{"c":"defrost","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off defrost of the #{device}"},{"c":"defrost","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Start defrost in #{device}"},{"c":"dehumidification","a":"getSupportedModes","e":null,"m":"GET","x":"PUBLIC","h":"What are the supported modes for dehumidification in the #{device}"},{"c":"dehumidification","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start dehumifying in the #{device}"},{"c":"dehumidification","a":"stop","e":null,"m":"POST","x":"PUBLIC","h":"Stop dehumifying in the #{device}"},{"c":"dehumidificationMode","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"What is the current mode of the #{device}"},{"c":"dehumidificationMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the dehumidification mode of the #{device} to #{predefinedDehumidificationMode}"},{"c":"detectedSoundType","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the type of sound detected by the #{device}"},{"c":"device","a":"cancel","e":null,"m":"POST","x":"INTERNAL","h":"Cancel the #{device}"},{"c":"device","a":"close","e":null,"m":"POST","x":"INTERNAL","h":"Close the #{device} [by #{number}%]"},{"c":"device","a":"closePartial","e":null,"m":"POST","x":"INTERNAL","h":"Close the #{device} a little"},{"c":"device","a":"connect","e":null,"m":"POST","x":"INTERNAL","h":"Add my devices to #{location}"},{"c":"device","a":"decrease","e":null,"m":"POST","x":"HIDDEN","h":"Decrease the #{device}"},{"c":"device","a":"decreasePartial","e":null,"m":"POST","x":"HIDDEN","h":"Decrease the #{device} a little"},{"c":"device","a":"getList","e":null,"m":"GET","x":"HIDDEN","h":"Show my devices in #{location}"},{"c":"device","a":"increase","e":null,"m":"POST","x":"HIDDEN","h":"Increase the #{device}"},{"c":"device","a":"increasePartial","e":null,"m":"POST","x":"HIDDEN","h":"Increase the #{device} a little"},{"c":"device","a":"move","e":null,"m":"POST","x":"INTERNAL","h":"Move the #{device} to #{rvcLocation}"},{"c":"device","a":"open","e":null,"m":"POST","x":"INTERNAL","h":"Open the #{device} [by #{number}%]"},{"c":"device","a":"openPartial","e":null,"m":"POST","x":"INTERNAL","h":"Open the #{device} a little"},{"c":"device","a":"pause","e":null,"m":"POST","x":"INTERNAL","h":"Pause the #{device}"},{"c":"device","a":"show","e":null,"m":"POST","x":"HIDDEN","h":"show device on #{device}"},{"c":"device","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start the #{device}"},{"c":"device","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"startCourse device on #{device}"},{"c":"device","a":"stop","e":null,"m":"POST","x":"INTERNAL","h":"Stop the #{device}"},{"c":"device","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the #{device}"},{"c":"device","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the #{device}"},{"c":"devicePlugin","a":"show","e":null,"m":"POST","x":"HIDDEN","h":"Show me the #{device} control page"},{"c":"deviceState","a":"getCloseStatus","e":null,"m":"GET","x":"INTERNAL","h":"Is the #{device} closed?"},{"c":"deviceState","a":"getOpenStatus","e":null,"m":"GET","x":"INTERNAL","h":"Is the #{device} open?"},{"c":"deviceState","a":"getProgress","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the progress of the #{device}"},{"c":"deviceState","a":"getRemainingTime","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the remaining time on the #{device}"},{"c":"deviceState","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the status of the #{device}"},{"c":"deviceState","a":"getSupportedModes","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the supported course of the #{device}"},{"c":"deviceState","a":"setMax","e":null,"m":"POST","x":"HIDDEN","h":"setMax deviceState on #{device}"},{"c":"deviceState","a":"setMin","e":null,"m":"POST","x":"HIDDEN","h":"setMin deviceState on #{device}"},{"c":"deviceState","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"setValue deviceState on #{device}"},{"c":"deviceTemperature","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the temperature of the #{device}"},{"c":"deviceTemperatureSetting","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Lower the temperature of the #{device} [by #{settingTemperatureDelta}]"},{"c":"deviceTemperatureSetting","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the setting temperature of the #{device}"},{"c":"deviceTemperatureSetting","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Raise the temperature of the #{device} [by #{settingTemperatureDelta}]"},{"c":"deviceTemperatureSetting","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"setValue deviceTemperatureSetting on #{device}"},{"c":"dewPoint","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"What is the dew point of the #{device}?"},{"c":"dishWashing","a":"cancel","e":null,"m":"POST","x":"PUBLIC","h":"Cancel dishwashing in the [#{predefinedCompartment}] #{device}"},{"c":"dishWashing","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the #{device}"},{"c":"dishWashing","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaining time on the [#{predefinedCompartment}] #{device}"},{"c":"dishWashing","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Notify me about the status of the [#{predefinedCompartment}] #{device}"},{"c":"dishWashing","a":"getSupportedCourses","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the supported courses for dishwashing in the [#{predefinedCompartment}] #{device}"},{"c":"dishWashing","a":"pause","e":null,"m":"POST","x":"PUBLIC","h":"Pause dishwashing in the #{device}"},{"c":"dishWashing","a":"setCourse","e":null,"m":"POST","x":"INTERNAL","h":"Set the diswashing course of the #{device} to #{mode}"},{"c":"dishWashing","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start dishwashing in the [#{predefinedCompartment}] #{device}"},{"c":"dishWashing","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"Start the #{device} in #{mode} dishwashing course"},{"c":"door","a":"close","e":null,"m":"POST","x":"PUBLIC","h":"Close the #{device}"},{"c":"door","a":"getCloseStatus","e":null,"m":"GET","x":"PUBLIC","h":"Is the #{device} closed?"},{"c":"door","a":"getOpenStatus","e":null,"m":"GET","x":"PUBLIC","h":"Is the #{device} open?"},{"c":"door","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"What is the status of the #{device} door?"},{"c":"door","a":"open","e":null,"m":"POST","x":"PUBLIC","h":"Open the #{device}"},{"c":"dressing","a":"cancel","e":null,"m":"POST","x":"INTERNAL","h":"Cancel dressing in the #{device}"},{"c":"dressing","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the #{device}"},{"c":"dressing","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaining time on the #{device}"},{"c":"dressing","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"What is the dressing status of the #{device}?"},{"c":"dressing","a":"getSupportedCourses","e":null,"m":"GET","x":"PUBLIC","h":"What are the supported courses for dressing in the #{device}?"},{"c":"dressing","a":"pause","e":null,"m":"POST","x":"INTERNAL","h":"Pause dressing in the #{device}"},{"c":"dressing","a":"start","e":null,"m":"POST","x":"HIDDEN","h":"Start dressing in the #{device}"},{"c":"dressing","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"Start dressing in the #{device} in the #{mode} mode"},{"c":"dressingMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the dressing mode to #{mode} on the #{device}"},{"c":"dryerLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light on the #{device}"},{"c":"dryerLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light on the #{device}"},{"c":"drying","a":"cancel","e":null,"m":"POST","x":"PUBLIC","h":"Cancel drying in the #{device}"},{"c":"drying","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the [#{predefinedCompartment}] #{device}"},{"c":"drying","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaining time on the #{device}"},{"c":"drying","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the drying status of the #{device}"},{"c":"drying","a":"getSupportedCourses","e":null,"m":"GET","x":"PUBLIC","h":"What are the supported courses for drying in the #{device}"},{"c":"drying","a":"pause","e":null,"m":"POST","x":"INTERNAL","h":"Pause drying in the #{device}"},{"c":"drying","a":"setCourse","e":null,"m":"POST","x":"INTERNAL","h":"Set the drying course of the #{device} to #{mode}"},{"c":"drying","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start drying in the #{device}"},{"c":"drying","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"Start the #{device} in the #{mode} mode"},{"c":"elevator","a":"call","e":null,"m":"POST","x":"PUBLIC","h":"Call the elevator"},{"c":"embeddedLight","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the status of the #{device} light"},{"c":"embeddedLight","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off the light of the #{device}"},{"c":"embeddedLight","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the light of the #{device}"},{"c":"emptying","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the emptying the dust bin on the #{device}"},{"c":"emptyingDuration","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the emptying duration of the #{device}"},{"c":"emptyingDuration","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the emptying duration of the #{device}"},{"c":"emptyingDuration","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Increase the emptying duration of the #{device}"},{"c":"enLarge","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off enlarge on the #{device}"},{"c":"enLarge","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on enlarge on the #{device}"},{"c":"energyMeter","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the energy consumption of the #{device}"},{"c":"extraCirculation","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off extra circulation on the #{device}"},{"c":"extraCirculation","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on extra circulation on the #{device}"},{"c":"fanMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the fan mode of the #{device} to #{predefinedFanMode}"},{"c":"fanMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the fan mode on the #{device}"},{"c":"fanSpeed","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the fan speed of the #{device}"},{"c":"fanSpeed","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the fan speed of the #{device}"},{"c":"fanSpeed","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the fan speed of the #{device}"},{"c":"fanSpeedLevel","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the fan speed of the #{device} to #{fanSpeedLevel}"},{"c":"fanSpeedMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the fan speed of the #{device} to #{predefinedFanSpeedMode}"},{"c":"feedPortion","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the feeder portion of the #{device} to #{feedPortion}"},{"c":"feeding","a":"start","e":null,"m":"POST","x":"INTERNAL","h":"Start feeding mode on the #{device}"},{"c":"filterUsage","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the filter usage of the #{device}"},{"c":"fineDustLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"What is the fine dust level of the #{device}?"},{"c":"finishTime","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"setValue finishTime on #{device}"},{"c":"formaldehyde","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the formaldehyde value of the #{device}"},{"c":"freezerTemperature","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the freezer temperature of the #{device}"},{"c":"freezerTemperature","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the #{device} freezer temperature to #{settingTemperature} #{predefinedSettingTemperatureUnit}"},{"c":"gasDetection","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the state of gas detection on the #{device}"},{"c":"gasMeter","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the gas meter reading on the #{device}"},{"c":"goodSleep","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off good sleep mode on the #{device}"},{"c":"goodSleep","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on good sleep mode on the #{device} for #{duration}"},{"c":"grayscale","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the grayscale on the #{device}"},{"c":"grayscale","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the grayscale on the #{device}"},{"c":"heatMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on heat mode on the #{device}"},{"c":"heatingTemperature","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Lower the heating temperature of the #{device} [by #{heatingTemperatureDelta}]"},{"c":"heatingTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the heating temperature of the #{device}"},{"c":"heatingTemperature","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the heating temperature of the #{device} [by #{heatingTemperatureDelta}]"},{"c":"heatingTemperature","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the heating temperature of the #{device} to #{heatingTemperature} [#{predefinedHeatingTemperatureUnit}]"},{"c":"highContrast","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the high contrast on the #{device}"},{"c":"highContrast","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the high contrast on the #{device}"},{"c":"hoodCamera","a":"show","e":null,"m":"POST","x":"INTERNAL","h":"Show me the hood camera the #{device}"},{"c":"hoodFanSpeedLevel","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the hood fan speed level of the #{device} to #{hoodFanSpeedLevel}"},{"c":"hoodFanSpeedMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the hood fan speed of the #{device} to #{predefinedHoodFanSpeedMode}"},{"c":"hoodLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the hood lamp on the #{device}"},{"c":"hoodLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the hood lamp on the #{device}"},{"c":"hoodLampBrightness","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Dim the hood lamp brightness on the #{device}"},{"c":"hoodLampBrightness","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Brighten the hood power on the #{device}"},{"c":"hoodPower","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the hood power on the #{device}"},{"c":"hoodPower","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the hood power on the #{device}"},{"c":"humidificationAmount","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Change the humidity of the #{device}"},{"c":"humidificationMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the humidifier mode of the #{device} to #{predefinedHumidificationMode}"},{"c":"humidity","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the humidity of the #{device} [by #{humidityDelta}%]"},{"c":"humidity","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the humidity of the #{device}"},{"c":"humidity","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the humidity of the #{device} [by #{humidityDelta}%]"},{"c":"humidity","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the humidity of the #{device} to #{humidity}%."},{"c":"iceMaker","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the ice maker on the #{device}"},{"c":"iceMaker","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the ice maker on the #{device}"},{"c":"illuminance","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me illuminance of the #{device}"},{"c":"imageViewer","a":"show","e":null,"m":"POST","x":"INTERNAL","h":"Show me the inside of the #{consumerDevice} on the #{device}"},{"c":"infraredLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me infrared level of the #{device}"},{"c":"infraredLevel","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the infrared level of the #{device} to #{infraredLevel}"},{"c":"invitationCode","a":"show","e":null,"m":"POST","x":"INTERNAL","h":"Show me the QR code to invite members [to #{location} in SmartThings]"},{"c":"language","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the #{device} language to #{mode}"},{"c":"light","a":"turnOff","e":null,"m":"POST","x":"HIDDEN","h":"Turn off the light of the #{device}"},{"c":"light","a":"turnOn","e":null,"m":"POST","x":"HIDDEN","h":"Turn on the #{device}"},{"c":"lightEffect","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off the #{device} #{predefinedLightEffect}"},{"c":"lightEffect","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the #{device} #{predefinedLightEffect} [for #{lightEffectTimer}]"},{"c":"lightingMode","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the lighting mode of the #{device}"},{"c":"lightingMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the lighting mode of the #{device} to #{predefinedLightingMode}"},{"c":"location","a":"unknown","e":null,"m":"GET","x":"HIDDEN","h":"unknown location on #{device}"},{"c":"locationMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the location mode of the #{device} to #{mode}"},{"c":"lock","a":"getCloseStatus","e":null,"m":"GET","x":"PUBLIC","h":"Is the #{device} closed?"},{"c":"lock","a":"getOpenStatus","e":null,"m":"GET","x":"PUBLIC","h":"Is the #{device} open?"},{"c":"lock","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the lock status of the #{device}"},{"c":"lock","a":"lock","e":null,"m":"POST","x":"PUBLIC","h":"Lock the #{device}"},{"c":"lock","a":"unlock","e":null,"m":"POST","x":"PUBLIC","h":"Unlock the #{device}"},{"c":"media","a":"fastForward","e":null,"m":"POST","x":"PUBLIC","h":"Fast forward the #{device}"},{"c":"media","a":"pause","e":null,"m":"POST","x":"PUBLIC","h":"Pause the #{device}"},{"c":"media","a":"play","e":null,"m":"POST","x":"PUBLIC","h":"Play the #{device}"},{"c":"media","a":"playNext","e":null,"m":"POST","x":"PUBLIC","h":"Play the next song on the #{device}"},{"c":"media","a":"playPrevious","e":null,"m":"POST","x":"PUBLIC","h":"Play the previous song on the #{device}"},{"c":"media","a":"rewind","e":null,"m":"POST","x":"PUBLIC","h":"Rewind the #{device}"},{"c":"media","a":"stop","e":null,"m":"POST","x":"PUBLIC","h":"Stop playing the #{device}"},{"c":"mediaInputSource","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the media input source of the #{device}"},{"c":"mediaInputSource","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the media input source of the #{device} to #{mediaInputSource}"},{"c":"mediaInputSource","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off #{mediaInputSource} on the #{device}"},{"c":"mediaInputSource","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the #{device} to #{mediaInputSource}"},{"c":"mediaRepeatMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the repeat mode of the #{device} to #{predefinedMediaRepeatMode}"},{"c":"mediaRepeatMode","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off repeat mode on the #{device}"},{"c":"mediaShuffle","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off shuffle on the #{device}"},{"c":"mediaShuffle","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on shuffle on the #{device}"},{"c":"microwave","a":"start","e":null,"m":"POST","x":"INTERNAL","h":"Start the #{device} for #{cookingTimer}"},{"c":"microwaveLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light of the #{device}"},{"c":"microwaveLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on light of the #{device}"},{"c":"microwaveTimer","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set #{cookingTimer} on the #{device}"},{"c":"mode","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the mode of the #{device}"},{"c":"mode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"setValue mode on #{device}"},{"c":"mode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"turnOff mode on #{device}"},{"c":"mold","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the mold level of the #{device}"},{"c":"motionSensor","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the motion sensor status of the #{device}"},{"c":"multiOutput","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the multi track sound on the #{device}"},{"c":"multiOutput","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the multi track sound on the #{device}"},{"c":"multiSystemOperator","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"What is the status of multi system operator on the #{device}?"},{"c":"music","a":"play","e":null,"m":"POST","x":"INTERNAL","h":"Play music on the #{device}"},{"c":"music","a":"stop","e":null,"m":"POST","x":"INTERNAL","h":"Stop music on the #{device}"},{"c":"mute","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Unmute the #{device}"},{"c":"mute","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Mute the #{device}"},{"c":"objectDetection","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the object detection status of the #{device}"},{"c":"odorLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the odor level status of the #{device}"},{"c":"ovenCamera","a":"show","e":null,"m":"POST","x":"INTERNAL","h":"Show what's inside the #{device}"},{"c":"ovenLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the lamp on the #{device}"},{"c":"ovenLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the lamp on the #{device}"},{"c":"panicAlarm","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the panic alarm status of the #{device}"},{"c":"pestControl","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the pest control status of the #{device}"},{"c":"phLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the ph level of the #{device}"},{"c":"pictureMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the picture mode of the #{device} to #{predefinedPictureMode}"},{"c":"powerCoolMode","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off power cool on the #{device}"},{"c":"powerCoolMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on power cool on the #{device}"},{"c":"powerFreezeMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off power freeze on the #{device}"},{"c":"powerFreezeMode","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on power freeze on the #{device}"},{"c":"powerMeter","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the power meter value of the #{device}"},{"c":"powerSource","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the power source of the #{device}"},{"c":"powerSwitch","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the power status of the #{device}"},{"c":"powerSwitch","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off the #{device}"},{"c":"powerSwitch","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the #{device}"},{"c":"precipitation","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the precipitation measurement of the #{device}"},{"c":"precipitationRatio","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the precipitation rate of the #{device}"},{"c":"precipitationSensor","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the precipitation state of the #{device}"},{"c":"presence","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the occupancy status of the #{device}"},{"c":"purifying","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off purify on the #{device}"},{"c":"purifying","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on purify on the #{device}"},{"c":"quickCooling","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off rapid cooling on the #{device}"},{"c":"quickCooling","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on rapid cooling on the #{device}"},{"c":"quietMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the quiet mode on the #{device}"},{"c":"quietMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the quiet mode on the #{device}"},{"c":"radonLevel","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the radon level reading on the #{device}"},{"c":"recharging","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Charge the #{device}"},{"c":"recording","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off recording on the #{device}"},{"c":"recording","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on recording on the #{device}"},{"c":"refrigerationTemperature","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the temperature of the #{device}"},{"c":"refrigerationTemperature","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the #{device} refrigeration temperature to #{settingTemperature} #{predefinedSettingTemperatureUnit}"},{"c":"refrigerationTemperatureSetting","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the refrigeration temperature setting of the #{device}"},{"c":"refrigeratorLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light in #{device}"},{"c":"refrigeratorLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light in #{device}"},{"c":"riceCooker","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaining time on the #{device}"},{"c":"riceCooker","a":"keepWarm","e":null,"m":"POST","x":"PUBLIC","h":"Keep the rice in the #{device} warm"},{"c":"riceCooker","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"Start the #{device} in #{predefinedRiceCookerMode}"},{"c":"rotation","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on rotation on the #{device}"},{"c":"scene","a":"execute","e":null,"m":"POST","x":"INTERNAL","h":"execute scene on #{device}"},{"c":"scene","a":"show","e":null,"m":"GET","x":"INTERNAL","h":"Show my scenes in #{location}"},{"c":"scent","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the scent of the #{device}"},{"c":"scent","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the scent of the #{device} to #{scent}"},{"c":"screenRotation","a":"change","e":null,"m":"POST","x":"INTERNAL","h":"Rotate the screen of the #{device}"},{"c":"screenRotation","a":"setHorizontal","e":null,"m":"POST","x":"INTERNAL","h":"Rotate the screen of the #{device} to landscape"},{"c":"screenRotation","a":"setVertical","e":null,"m":"POST","x":"INTERNAL","h":"Rotate the screen of the #{device} to portrait"},{"c":"securityMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the security mode of the #{device} to #{mode}"},{"c":"sleepDetection","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Let me know the sleep detection status of the #{device}"},{"c":"sleepMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the sleep mode on the #{device}"},{"c":"sleepTimer","a":"cancel","e":null,"m":"POST","x":"PUBLIC","h":"turn off the sleep timer on the #{device}"},{"c":"sleepTimer","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"set a sleep timer on the #{device} for #{duration}"},{"c":"smartControl","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the smart control status of the #{device}"},{"c":"smokeDetection","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the smoke detection status of the #{device}"},{"c":"soundDetectionSetting","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off sound detection on the #{device}"},{"c":"soundDetectionSetting","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on sound detection on the #{device}"},{"c":"soundMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the sound mode of the #{device} to #{predefinedSoundMode}"},{"c":"soundOutput","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Change the sound output of the #{device} to #{predefinedSoundOutput}"},{"c":"soundPressureLevel","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the noise of the #{device}"},{"c":"soundSensor","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the sound sensor status of the #{device}"},{"c":"speedMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the speed mode on the #{device}"},{"c":"speedMode","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the speed mode on the #{device}"},{"c":"suctionPower","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the suction power of the #{device} to #{predefinedSuctionPowerMode}"},{"c":"supportedDevices","a":"show","e":null,"m":"GET","x":"INTERNAL","h":"Show me the supported device list"},{"c":"temperatureAlarm","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the temperature alarm status of the #{device}"},{"c":"thermostatMode","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the operation status of the #{device}"},{"c":"thermostatMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the #{device} to #{predefinedThermostatMode}"},{"c":"thermostatMode","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off [the #{predefinedThermostatMode} mode on] the #{device}"},{"c":"thermostatMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on [the #{predefinedThermostatMode} mode on] the #{device}"},{"c":"thermostatOperatingState","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the operating status of the #{device}"},{"c":"touchLock","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off touch lock on the #{device}"},{"c":"touchLock","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on touch lock on the #{device}"},{"c":"trashCan","a":"empty","e":null,"m":"POST","x":"INTERNAL","h":"Empty the dustbin of the #{device}"},{"c":"turboCleaningMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the turbo cleaning mode of the #{device} to #{predefinedTurboCleaningMode}"},{"c":"turboCleaningMode","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off the turbo mode on the #{device}"},{"c":"turboCleaningMode","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on the turbo mode on the #{device}"},{"c":"tvocLevel","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the total organic volatile compound on the #{device}"},{"c":"ultrafineDustLevel","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the status of ultrafine dust on the #{device}"},{"c":"ultravioletIndex","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the ultraviolet index of the #{device}"},{"c":"ventMode","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"let me know the mode of the #{device}"},{"c":"ventMode","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the mode of the #{device} to #{predefinedVentMode}"},{"c":"ventStrength","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the strength of the #{device}"},{"c":"ventStrength","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set strength of the #{device} to #{predefinedVentStrength}"},{"c":"ventilation","a":"turnOff","e":null,"m":"POST","x":"PUBLIC","h":"Turn off ventilation on the #{device}"},{"c":"ventilation","a":"turnOn","e":null,"m":"POST","x":"PUBLIC","h":"Turn on ventilation on the #{device}"},{"c":"video","a":"play","e":null,"m":"POST","x":"INTERNAL","h":"Play a video on the #{device}"},{"c":"video","a":"stop","e":null,"m":"POST","x":"INTERNAL","h":"stop the video on the #{device}"},{"c":"videoDescription","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"turn off the video description on the #{device}"},{"c":"videoDescription","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"turn on the video description on the #{device}"},{"c":"videoStream","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"turn off video stream on the #{device}"},{"c":"videoStream","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"turn on video stream on the #{device}"},{"c":"virusDoctor","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"turn off the virus doctor on the #{device}"},{"c":"virusDoctor","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"turn on the virus doctor on the #{device}"},{"c":"voiceGuide","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the voice guide on the #{device}"},{"c":"voiceGuide","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"turn on the voice guide on the #{device}"},{"c":"voltage","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the voltage of the #{device}"},{"c":"volume","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease volume on the #{device} [by #{volumeLevelDelta}]"},{"c":"volume","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"what is the volume on the #{device}?"},{"c":"volume","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the volume on the #{device} [by #{volumeLevelDelta}]"},{"c":"volume","a":"setHalf","e":null,"m":"POST","x":"PUBLIC","h":"Set the volume of the #{device} to half"},{"c":"volume","a":"setMax","e":null,"m":"POST","x":"PUBLIC","h":"Set the volume of the #{device} to maximum"},{"c":"volume","a":"setMin","e":null,"m":"POST","x":"PUBLIC","h":"Set the volume of the #{device} to minimum"},{"c":"volume","a":"setValue","e":null,"m":"POST","x":"PUBLIC","h":"Set the volume of the #{device} to #{volumeLevel}"},{"c":"washerLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the lamp in the #{device}"},{"c":"washerLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the lamp in the #{device}"},{"c":"washing","a":"cancel","e":null,"m":"POST","x":"PUBLIC","h":"Cancel washing in the [#{predefinedCompartment}] #{device}"},{"c":"washing","a":"getProgress","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the progress of the [#{predefinedCompartment}] #{device}"},{"c":"washing","a":"getRemainingTime","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the remaining time on the #{device}"},{"c":"washing","a":"getStatus","e":null,"m":"GET","x":"PUBLIC","h":"what is the washing status of the #{device}"},{"c":"washing","a":"getSupportedCourses","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the supported laundry course on the #{device}"},{"c":"washing","a":"pause","e":null,"m":"POST","x":"PUBLIC","h":"Pause the laundry on the #{device}"},{"c":"washing","a":"setCourse","e":null,"m":"POST","x":"INTERNAL","h":"Set the washing course of the #{device} to #{mode}"},{"c":"washing","a":"start","e":null,"m":"POST","x":"PUBLIC","h":"start washing in the #{device}"},{"c":"washing","a":"startCourse","e":null,"m":"POST","x":"INTERNAL","h":"Start the #{device} in #{mode} mode"},{"c":"water","a":"decreaseDispenseAmount","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the dispense amount on the #{device} [for #{foodRecipeName}] [by #{waterAmountDelta}#{predefinedWaterAmountUnit}] [in #{predefinedWaterPurifyingMode}]"},{"c":"water","a":"dispense","e":null,"m":"POST","x":"INTERNAL","h":"Give me #{waterAmount}#{predefinedWaterAmountUnit} [for #{foodRecipeName}] from the #{device} [in #{predefinedWaterPurifyingMode}]"},{"c":"water","a":"getDispenseAmount","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the water amount of the #{device}"},{"c":"water","a":"setAmountLevel","e":null,"m":"POST","x":"INTERNAL","h":"Change the #{device} water volume level to #{predefinedWaterAmountLevel}"},{"c":"water","a":"setDispenseAmount","e":null,"m":"POST","x":"INTERNAL","h":"Set the water discharge amount [for #{foodRecipeName}] to #{waterAmount}#{predefinedWaterAmountUnit} on the #{device}"},{"c":"waterHeating","a":"getStatus","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the water heating status of the #{device}"},{"c":"waterHeating","a":"getSupportedModes","e":null,"m":"GET","x":"PUBLIC","h":"What are the supported modes for water heating in the #{device}"},{"c":"waterHeating","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off water heating on the #{device}"},{"c":"waterHeating","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on water heating on the #{device}"},{"c":"waterHeatingMode","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the mode of the #{device}"},{"c":"waterHeatingMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the water heating mode of the #{device} to #{predefinedWaterHeatingMode}"},{"c":"waterHeatingTemperature","a":"decrease","e":null,"m":"POST","x":"PUBLIC","h":"Decrease the water heating temperature of the #{device} [by #{waterHeatingTemperatureDelta}]"},{"c":"waterHeatingTemperature","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the water heating temperature of the #{device}"},{"c":"waterHeatingTemperature","a":"increase","e":null,"m":"POST","x":"PUBLIC","h":"Increase the water heating temperature of the #{device} [by #{waterHeatingTemperatureDelta}] "},{"c":"waterHeatingTemperature","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the water heating temperature of the #{device} to #{waterHeatingTemperature} [#{predefinedWaterHeatingTemperatureUnit}]"},{"c":"waterPurifyingMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the water amount on the #{device} [for #{foodRecipeName}] to #{waterAmount}#{predefinedWaterAmountUnit} [in #{predefinedWaterPurifyingMode}]"},{"c":"weight","a":"getValue","e":null,"m":"GET","x":"INTERNAL","h":"Tell me the weight of the #{device}"},{"c":"windDirection","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the wind direction of the #{device} to #{predefinedWindDirection}"},{"c":"windFreeMode","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off wind free on the #{device}"},{"c":"windFreeMode","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on wind free on the #{device}"},{"c":"windSpeed","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the wind speed of the #{device}"},{"c":"windStrength","a":"decrease","e":null,"m":"POST","x":"INTERNAL","h":"Decrease the wind strength of the #{device}"},{"c":"windStrength","a":"getValue","e":null,"m":"GET","x":"PUBLIC","h":"Tell me the wind strength of the #{device}"},{"c":"windStrength","a":"increase","e":null,"m":"POST","x":"INTERNAL","h":"Increase the wind strength of the #{device}"},{"c":"windStrengthLevel","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the wind strength of the #{device} to level #{windStrengthLevel}"},{"c":"windStrengthMode","a":"setValue","e":null,"m":"POST","x":"INTERNAL","h":"Set the wind strength of the #{device} to #{predefinedWindStrengthMode}"},{"c":"wineRefrigeratorLamp","a":"turnOff","e":null,"m":"POST","x":"INTERNAL","h":"Turn off the light on the #{device}"},{"c":"wineRefrigeratorLamp","a":"turnOn","e":null,"m":"POST","x":"INTERNAL","h":"Turn on the light on the #{device}"}]
"""#

    public static let commands: [HomeBixbyVoiceCommand] = {
        let data = Data(sourceJSON.utf8)
        return (try! JSONDecoder().decode([SourceCommand].self, from: data)).map {
            HomeBixbyVoiceCommand(
                capability: $0.c,
                action: $0.a,
                enumeration: $0.e,
                method: $0.m,
                accessLevel: $0.x,
                hint: $0.h
            )
        }
    }()

    private static let normalizedLookup: [String: HomeBixbyVoiceCommand] = {
        normalizedMatches.mapValues { $0[0] }
    }()

    private static let normalizedMatches: [String: [HomeBixbyVoiceCommand]] = {
        var matches: [String: [HomeBixbyVoiceCommand]] = [:]
        for command in commands {
            for utterance in alternatives(for: command) {
                matches[normalize(utterance), default: []].append(command)
            }
        }
        return matches
    }()

    public static let capabilityNames: [String] = [
        "accelerationSensor",
        "activityLightingMode",
        "activitySensor",
        "airConditionerFanMode",
        "airConditionerMode",
        "airPurifierFanMode",
        "airQualitySensor",
        "alarm",
        "atmosphericPressureMeasurement",
        "audioMute",
        "audioStream",
        "audioVolume",
        "battery",
        "bodyMassIndexMeasurement",
        "bodyWeightMeasurement",
        "bypassable",
        "carbonDioxideHealthConcern",
        "carbonDioxideMeasurement",
        "carbonMonoxideDetector",
        "carbonMonoxideMeasurement",
        "chime",
        "colorControl",
        "colorMode",
        "colorTemperature",
        "consumable",
        "contactSensor",
        "custom.multiSystemOperator",
        "dewPoint",
        "dishwasherMode",
        "dishwasherOperatingState",
        "doorControl",
        "dryerMode",
        "dryerOperatingState",
        "dustHealthConcern",
        "dustSensor",
        "elevatorCall",
        "energyMeter",
        "equivalentCarbonDioxideMeasurement",
        "fanOscillationMode",
        "fanSpeed",
        "feederOperatingState",
        "feederPortion",
        "filterState",
        "filterStatus",
        "fineDustHealthConcern",
        "fineDustSensor",
        "formaldehydeMeasurement",
        "garageDoorControl",
        "gasDetector",
        "gasMeter",
        "humidifierMode",
        "illuminanceMeasurement",
        "infraredLevel",
        "keypadInput",
        "languageSetting",
        "locationMode",
        "lock",
        "mediaGroup",
        "mediaInputSource",
        "mediaPlayback",
        "mediaPlaybackRepeat",
        "mediaPlaybackShuffle",
        "mediaTrackControl",
        "mode",
        "moldHealthConcern",
        "motionSensor",
        "musicPlayer",
        "objectDetection",
        "occupancySensor",
        "odorSensor",
        "operatingState",
        "ovenMode",
        "ovenOperatingState",
        "ovenSetpoint",
        "pHMeasurement",
        "panicAlarm",
        "pestControl",
        "powerMeter",
        "powerSource",
        "precipitationMeasurement",
        "precipitationRate",
        "precipitationSensor",
        "presenceSensor",
        "radonHealthConcern",
        "radonMeasurement",
        "rapidCooling",
        "refrigeration",
        "refrigerationSetpoint",
        "relativeBrightness",
        "relativeHumidityMeasurement",
        "remoteControlStatus",
        "robotCleanerCleaningMode",
        "robotCleanerMovement",
        "robotCleanerTurboMode",
        "samsungTV",
        "samsungim.bixby",
        "scent",
        "securitySystem",
        "sleepSensor",
        "smokeDetector",
        "soundDetection",
        "soundPressureLevel",
        "soundSensor",
        "statelessAirCleanerModeButton",
        "statelessAudioMuteButton",
        "statelessAudioVolumeButton",
        "statelessChannelButton",
        "statelessCurtainPowerButton",
        "statelessFanspeedButton",
        "statelessFanspeedModeButton",
        "statelessHumidifierModeButton",
        "statelessPowerButton",
        "statelessPowerToggleButton",
        "statelessRobotCleanerActionButton",
        "statelessRobotCleanerHomeButton",
        "statelessRobotCleanerToggleButton",
        "statelessSetChannelButton",
        "statelessSetChannelByNameButton",
        "statelessTemperatureButton",
        "statelessVolumeButtonWithRepetition",
        "switch",
        "switchLevel",
        "tV",
        "tamperAlert",
        "temperatureAlarm",
        "temperatureMeasurement",
        "thermostat",
        "thermostatCoolingSetpoint",
        "thermostatFanMode",
        "thermostatHeatingSetpoint",
        "thermostatMode",
        "thermostatOperatingState",
        "timedSession",
        "tone",
        "tvChannel",
        "tvocHealthConcern",
        "tvocMeasurement",
        "ultravioletIndex",
        "valve",
        "veryFineDustHealthConcern",
        "veryFineDustSensor",
        "videoStream",
        "voltageMeasurement",
        "washerMode",
        "washerOperatingState",
        "waterSensor",
        "windSpeed",
        "windowShade",
        "windowShadeLevel"
    ]

    public static var instructionSummary: String {
        let actionNames = Set(commands.map(\.action)).sorted().joined(separator: ", ")
        let capabilityExamples = commands.prefix(80).map(\.capabilityAction).joined(separator: ", ")
        return """
        Bixby Home Studio voice-intent coverage is enabled. Interpret commands using the Bixby command grammar:
        - Source command count: \(sourceCommandCount) voice intents across \(sourceCapabilityCount) SmartThings capability records.
        - Supported Bixby action names include: \(actionNames).
        - Capability/action examples: \(capabilityExamples).
        - Treat #{Device}, #{device}, location, mode, duration, temperature, and numeric values as slots to extract, not literal words.
        - Map GET methods to status/query intents and POST methods to command execution drafts.
        """
    }

    public static func alternatives(for command: HomeBixbyVoiceCommand, deviceName: String = "bedroom light") -> [String] {
        let canonical = render(command.hint, deviceName: deviceName)
        let lowerCanonical = decapitalized(canonical)
        let actionPhrase = phrase(for: command)
        let capabilityPhrase = humanize(command.capability)
        let modePhrase = command.enumeration.map(humanize)

        let alternatives = [
            canonical,
            "Please \(lowerCanonical)",
            "Can you \(lowerCanonical)?",
            "Could you \(actionPhrase) on the \(deviceName)?",
            "I want to \(actionPhrase) for the \(deviceName).",
            "Ask the \(deviceName) to \(actionPhrase).",
            "Use \(capabilityPhrase) to \(actionPhrase) on the \(deviceName).",
            "For the \(deviceName), \(actionPhrase).",
            "\(deviceName): \(actionPhrase).",
            modePhrase.map { "Set the \(deviceName) to \($0) mode." } ?? "Set the \(deviceName) so it will \(actionPhrase)."
        ]

        return alternatives.map(cleanSpacing)
    }

    public static func command(matching utterance: String, deviceName: String = "bedroom light") -> HomeBixbyVoiceCommand? {
        if deviceName == "bedroom light" {
            return normalizedLookup[normalize(utterance)]
        }
        let normalizedUtterance = normalize(utterance)
        return commands.first { command in
            alternatives(for: command, deviceName: deviceName).contains { normalize($0) == normalizedUtterance }
        }
    }

    public static func commands(matching utterance: String, deviceName: String = "bedroom light") -> [HomeBixbyVoiceCommand] {
        if deviceName == "bedroom light" {
            return normalizedMatches[normalize(utterance)] ?? []
        }
        let normalizedUtterance = normalize(utterance)
        return commands.filter { command in
            alternatives(for: command, deviceName: deviceName).contains { normalize($0) == normalizedUtterance }
        }
    }

    public static func capabilityActionPairs(limit: Int? = nil) -> [String] {
        let values = commands.map(\.capabilityAction)
        guard let limit else { return values }
        return Array(values.prefix(limit))
    }

    private static func phrase(for command: HomeBixbyVoiceCommand) -> String {
        let capability = humanize(command.capability)
        let mode = command.enumeration.map(humanize)
        let action = command.action.lowercased()

        if action.contains("turnon") || action == "on" { return "turn on the \(capability)" }
        if action.contains("turnoff") || action == "off" { return "turn off the \(capability)" }
        if action.contains("open") { return "open the \(capability)" }
        if action.contains("close") { return "close the \(capability)" }
        if action.contains("start") { return "start the \(capability)" }
        if action.contains("stop") { return "stop the \(capability)" }
        if action.contains("pause") { return "pause the \(capability)" }
        if action.contains("resume") { return "resume the \(capability)" }
        if action.contains("increase") { return "increase the \(capability)" }
        if action.contains("decrease") { return "decrease the \(capability)" }
        if action.contains("set") { return "set \(capability)" + mode.map { " to \($0)" }.orEmpty }
        if action.contains("get") || command.method.uppercased() == "GET" { return "tell me the \(capability) status" }
        return "run \(humanize(command.action)) for the \(capability)"
    }

    private static func render(_ hint: String, deviceName: String) -> String {
        hint
            .replacingOccurrences(of: "#{Device}", with: deviceName)
            .replacingOccurrences(of: "#{device}", with: deviceName)
            .replacingOccurrences(of: "#{Location}", with: "living room")
            .replacingOccurrences(of: "#{location}", with: "living room")
            .replacingOccurrences(of: "#{Mode}", with: "auto")
            .replacingOccurrences(of: "#{mode}", with: "auto")
            .replacingOccurrences(of: "#{Temperature}", with: "72")
            .replacingOccurrences(of: "#{temperature}", with: "72")
            .replacingOccurrences(of: "#{Duration}", with: "30 minutes")
            .replacingOccurrences(of: "#{duration}", with: "30 minutes")
            .replacingOccurrences(of: "#{Number}", with: "50")
            .replacingOccurrences(of: "#{number}", with: "50")
    }

    private static func humanize(_ value: String) -> String {
        let spaced = value.replacingOccurrences(
            of: "([a-z0-9])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
        return spaced
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private static func decapitalized(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.lowercased() + value.dropFirst()
    }

    private static func cleanSpacing(_ value: String) -> String {
        value
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
