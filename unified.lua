-- unified.lua
-- A single Hammerspoon script for transcription, grammar correction, assistant interaction,
-- and dynamic shortcut configuration.
--
-- Default shortcuts:
--   Grammar Fix:               alt+cmd+G
--   Transcription:             alt+cmd+K
--   AI Assistant:              alt+cmd+O
--   Edit Grammar Prompt:       ctrl+alt+cmd+P
--   Edit Assistant Prompt:     ctrl+alt+cmd+A
--   Toggle Auto-Grammar:       ctrl+alt+cmd+T
--   Toggle Condensed Mode:     ctrl+alt+cmd+C
--   View History:              ctrl+alt+cmd+H
--   Shortcut Menu:             ctrl+alt+cmd+S
--
-- Press ESC during recording to cancel the recording.
--
-- Changes from previous version:
-- - Introduced callGroqTranscribe() for transcription (used by both stopAndTranscribe and assistant logic)
-- - Reuse startRecording() and stopAndTranscribe() in assistantInteract() to avoid code duplication.

-----------------------------------------
-- Configuration & Setup
-----------------------------------------
-- local audioFile = "/Users/unclecode/.audio/output.m4a"
local ffmpegPath = "/opt/homebrew/bin/ffmpeg"

-- New paths (using script directory as base)
local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)")
local audioFile = scriptDir .. "audio/output.m4a"
local apiKeyPath = scriptDir .. ".api_key"
local groqKey = hs.execute("cat " .. apiKeyPath .. " | grep GROQ_API_KEY | cut -d'=' -f2"):gsub("%s+", "")
local openaiKey = hs.execute("cat " .. apiKeyPath .. " | grep OPENAI_API_KEY | cut -d'=' -f2"):gsub("%s+", "")


-- Styles
local alertStyle = {
    fillColor = {red = 0, green = 0, blue = 0, alpha = 0.8},
    strokeColor = {red = 0.5, green = 0, blue = 0.5, alpha = 0.8},
    textColor = {red = 1, green = 1, blue = 1, alpha = 0.8},
    textSize = 16,
    radius = 10
}

local scriptDir = debug.getinfo(1, "S").source:match("@?(.*/)")
local promptFile = scriptDir .. "grammar_prompt.md"
local assistantPromptFile = scriptDir .. "assistant_prompt.md"
local conversationHistoryFile = scriptDir .. "conversation_history.json"

-- Read config file for audio device
local configFile = scriptDir .. "config"
local audioDevice = ":0" -- default fallback
do
    local f = io.open(configFile, "r")
    if f then
        for line in f:lines() do
            if line:match("^AUDIO_DEVICE=") then
                audioDevice = ":" .. line:gsub("AUDIO_DEVICE=", "")
                break
            end
        end
        f:close()
    end
end

-- Print device
print("Using audio device: " .. audioDevice)

-- Read grammar prompt
local systemPrompt = ""
do
    local f = io.open(promptFile, "r")
    if f then
        systemPrompt = f:read("*all")
        f:close()
    else
        hs.alert.show("Error: Could not open grammar_prompt.md", alertStyle)
    end
end

-- Read assistant prompt
local assistantPrompt = ""
do
    local f = io.open(assistantPromptFile, "r")
    if f then
        assistantPrompt = f:read("*all")
        f:close()
    else
        hs.alert.show("Error: Could not open assistant_prompt.md", alertStyle)
    end
end

-----------------------------------------
-- Settings & Flags
-----------------------------------------
local function getBooleanSetting(key, default)
    local val = hs.settings.get(key)
    if val == nil then return default end
    return val
end
local autoGrammarAfterTranscribe = getBooleanSetting("autoGrammarAfterTranscribe", false)
local condensedMode = getBooleanSetting("condensedMode", false)
local menuBar = nil

-----------------------------------------
-- Conversation History
-----------------------------------------
local conversationHistory = {}
local MAX_HISTORY = 50

local function addToHistory(role, content)
    table.insert(conversationHistory, { role = role, content = content })
    while #conversationHistory > MAX_HISTORY do
        table.remove(conversationHistory, 1)
    end
    local historyFile = io.open(conversationHistoryFile, "w")
    if historyFile then
        historyFile:write(hs.json.encode(conversationHistory))
        historyFile:close()
    end
end

local function loadConversationHistory()
    local historyFile = io.open(conversationHistoryFile, "r")
    if historyFile then
        local content = historyFile:read("*all")
        historyFile:close()
        conversationHistory = hs.json.decode(content) or {}
    end
end
loadConversationHistory()

-----------------------------------------
-- UI Indicator & Status
-----------------------------------------
local mouseIndicator = nil
local emojiIndicator = nil
local mouseWatcher = nil
local pulseTimer = nil

local STATUS_EMOJIS = {
    recording = "🔴",
    processing = "⏳",
    done = "✅",
    error = "❌"
}

local function updateIndicatorPosition()
    if mouseIndicator and emojiIndicator then
        local mousePos = hs.mouse.absolutePosition()
        mouseIndicator:setTopLeft({x = mousePos.x + 20, y = mousePos.y - 20})
        emojiIndicator:setTopLeft({x = mousePos.x + 24, y = mousePos.y - 13})
    end
end

local function startPulsingAnimation()
    local alpha = 0.7
    local increasing = false
    pulseTimer = hs.timer.doEvery(0.05, function()
        if not mouseIndicator then return end
        if increasing then
            alpha = alpha + 0.03
            if alpha >= 0.7 then increasing = false end
        else
            alpha = alpha - 0.03
            if alpha <= 0.3 then increasing = true end
        end
        mouseIndicator:setFillColor({red = 1, green = 0, blue = 0, alpha = alpha})
    end)
end

local function setStatus(status)
    if not emojiIndicator then return end
    emojiIndicator:hide()
    emojiIndicator:setText(STATUS_EMOJIS[status] or "⏳")
    emojiIndicator:show()
end

local function toggleMouseIndicator(newStatus)
    if newStatus == nil then
        if mouseIndicator then
            mouseIndicator:delete()
            mouseIndicator = nil
            emojiIndicator:delete()
            emojiIndicator = nil
            mouseWatcher:stop()
            mouseWatcher = nil
            if pulseTimer then
                pulseTimer:stop()
                pulseTimer = nil
            end
        end
        return
    end

    if mouseIndicator then
        setStatus(newStatus)
        return
    end

    local mousePos = hs.mouse.absolutePosition()
    mouseIndicator = hs.drawing.circle(hs.geometry.rect(mousePos.x + 20, mousePos.y - 20, 31, 30))
    mouseIndicator:setFill(true)
    mouseIndicator:setFillColor({red = 1, green = 0, blue = 0, alpha = 0.7})
    mouseIndicator:setStroke(false)
    mouseIndicator:show()

    emojiIndicator = hs.drawing.text(hs.geometry.rect(mousePos.x + 26, mousePos.y - 13, 20, 20),
        STATUS_EMOJIS[newStatus])
    emojiIndicator:setTextSize(16)
    emojiIndicator:show()

    mouseWatcher = hs.timer.doEvery(0.1, updateIndicatorPosition)
    startPulsingAnimation()
end

-----------------------------------------
-- Helper Functions
-----------------------------------------
local function getSystemPrompt()
    local basePrompt = systemPrompt
    if condensedMode then
        basePrompt = basePrompt .. "\n\nAnd one more thing, make sure to edit the text in a condensed way that keeps all main points but makes it as concise as possible without losing important information."
    end
    return basePrompt
end

local function sendKeystroke(modifiers, key)
    hs.eventtap.keyStroke(modifiers, key, 0)
end

local function callOpenAI(sysPrompt, userText)
    local jsonBody = hs.json.encode({
        model = "gpt-4o-mini",
        messages = {
            { role = "system", content = getSystemPrompt() },
            { role = "user", content = userText }
        },
        temperature = 0
    })
    local curlCmd = string.format(
        '/usr/bin/curl "https://api.openai.com/v1/chat/completions" ' ..
        '-H "Authorization: Bearer %s" ' ..
        '-H "Content-Type: application/json" ' ..
        '-d %q',
        openaiKey, jsonBody
    )
    local response = hs.execute(curlCmd)
    local json = hs.json.decode(response)
    if not json or not json.choices or not json.choices[1] or not json.choices[1].message then
        return nil, "No valid response"
    end
    return json.choices[1].message.content, nil
end

local function callAssistantAPI(userInput, context)
    local messages = {{ role = "system", content = assistantPrompt }}
    for _, msg in ipairs(conversationHistory) do
        table.insert(messages, msg)
    end
    
    -- If context is provided, wrap it in selected_text tags
    local finalUserInput = userInput
    if context then
        finalUserInput = string.format("%s\n\n<selected_text>This is the text I have selected: %s</selected_text>", 
            userInput, context)
    end
    
    table.insert(messages, { role = "user", content = finalUserInput })

    local jsonBody = hs.json.encode({
        model = "gpt-4o-mini",
        messages = messages,
        temperature = 0.7
    })

    print(jsonBody)
    
    local curlCmd = string.format(
        '/usr/bin/curl "https://api.openai.com/v1/chat/completions" ' ..
        '-H "Authorization: Bearer %s" ' ..
        '-H "Content-Type: application/json" ' ..
        '-d %q',
        openaiKey, jsonBody
    )
    local response = hs.execute(curlCmd)
    local json = hs.json.decode(response)
    print(response)
    if not json or not json.choices or not json.choices[1] or not json.choices[1].message then
        return nil, "No valid response"
    end
    addToHistory("user", finalUserInput)
    addToHistory("assistant", json.choices[1].message.content)
    return json.choices[1].message.content, nil
end

-----------------------------------------
-- Transcription (Groq)
-----------------------------------------
local recordingTask = nil
local escHotkey = nil

local function cancelRecording()
    if recordingTask and recordingTask:isRunning() then
        recordingTask:terminate()
        recordingTask = nil
        if hs.fs.attributes(audioFile) then
            os.remove(audioFile)
        end
        toggleMouseIndicator()
        if escHotkey then
            escHotkey:delete()
            escHotkey = nil
        end
    end
end

local function startRecording()
    if hs.fs.attributes(audioFile) then
        os.remove(audioFile)
    end
    recordingTask = hs.task.new(ffmpegPath, function() end,
        {"-f", "avfoundation", "-i", audioDevice, "-c:a", "aac", audioFile})
    if recordingTask:start() then
        hs.timer.doAfter(0.5, function()
            hs.sound.getByName("Blow"):play()
            toggleMouseIndicator("recording")
        end)
        if escHotkey then escHotkey:delete() end
        escHotkey = hs.hotkey.bind({}, "escape", function()
                        cancelRecording(); return false end)
    else
        hs.alert.show("Failed to start recording", alertStyle)
    end
end

local function callGroqTranscribe(filePath)
    local curlCmd = string.format(
        '/usr/bin/curl "https://api.groq.com/openai/v1/audio/transcriptions" ' ..
        '-H "Authorization: Bearer %s" ' ..
        '-H "Content-Type: multipart/form-data" ' ..
        '-F file=@%s ' ..
        '-F model=whisper-large-v3-turbo ' ..
        '-F temperature=0 ' ..
        '-F response_format=json ' ..
        '-F language=en',
        groqKey, filePath
    )
    local response = hs.execute(curlCmd)
    local json = hs.json.decode(response)
    if not json or not json.text then
        return nil, "Error in transcription!"
    end
    return json.text, nil
end

-- stopAndTranscribe(callback): Stops recording, transcribes audio, and calls callback(text)
-- If no callback provided, uses default logic (autoGrammarAfterTranscribe)
local function stopAndTranscribe(callback)
    if recordingTask and recordingTask:isRunning() then
        recordingTask:terminate()
        recordingTask = nil
        if escHotkey then
            escHotkey:delete()
            escHotkey = nil
        end
    end
    toggleMouseIndicator("processing")
    hs.timer.usleep(100000)
    hs.timer.doAfter(0.1, function()
        local text, err = callGroqTranscribe(audioFile)
        if not text then
            toggleMouseIndicator("error")
            hs.timer.doAfter(1, function() toggleMouseIndicator() end)
            hs.alert.show(err or "Unknown error", alertStyle)
            hs.sound.getByName("Basso"):play()
            return
        end

        if callback then
            -- If a callback is provided, let the callback handle text
            callback(text)
        else
            -- Default behavior: optional grammar fix, then paste
            if autoGrammarAfterTranscribe then
                local result, gErr = callOpenAI(systemPrompt, text)
                if result then
                    text = result
                else
                    hs.alert.show("Grammar fix failed: " .. (gErr or "Unknown"), alertStyle)
                end
            end
            hs.pasteboard.setContents(text)
            hs.timer.usleep(500000)
            hs.eventtap.keyStroke({"cmd"}, "v")
            hs.sound.getByName("Blow"):play()
            toggleMouseIndicator("done")
            hs.timer.doAfter(1, function() toggleMouseIndicator() end)
        end
    end)
end

local function transcriptionToggle()
    if recordingTask and recordingTask:isRunning() then
        stopAndTranscribe()
    else
        startRecording()
    end
end

-----------------------------------------
-- Grammar Fix
-----------------------------------------
local function grammarFix()
    sendKeystroke({"cmd"}, "c")
    hs.timer.doAfter(0.5, function()
        local selectedText = hs.pasteboard.getContents()
        if not selectedText or selectedText == "" then
            hs.alert.show("No text selected", alertStyle)
            hs.sound.getByName("Basso"):play()
            return
        end
        toggleMouseIndicator("processing")
        hs.timer.usleep(100000)
        hs.timer.doAfter(0.1, function()
            local result, err = callOpenAI(systemPrompt, selectedText)
            if not result then
                toggleMouseIndicator("error")
                hs.timer.doAfter(1, function() toggleMouseIndicator() end)
                hs.alert.show("Error: " .. (err or "Unknown"), alertStyle)
                hs.sound.getByName("Basso"):play()
                return
            end
            hs.pasteboard.setContents(result)
            hs.timer.usleep(500000)
            sendKeystroke({"cmd"}, "v")
            hs.sound.getByName("Blow"):play()
            toggleMouseIndicator("done")
            hs.timer.doAfter(1, function() toggleMouseIndicator() end)
        end)
    end)
end

-----------------------------------------
-- Assistant Interaction
-----------------------------------------
local function assistantInteract()
    -- First check if there's any selected text by comparing clipboard before and after
    local originalClipboard = hs.pasteboard.getContents()
    sendKeystroke({"cmd"}, "c")
    hs.timer.doAfter(0.1, function()  -- Small delay to ensure copy completes
        local newClipboard = hs.pasteboard.getContents()
        local selectedText = nil
        
        -- If clipboard changed, we have selected text
        if newClipboard and newClipboard ~= originalClipboard then
            selectedText = newClipboard
            -- Restore original clipboard
            hs.pasteboard.setContents(originalClipboard)
        end
        
        if recordingTask and recordingTask:isRunning() then
            -- Stop recording and process transcription, then call assistant
            stopAndTranscribe(function(transcribedText)
                -- addToHistory("user", transcribedText)
                local result, err = callAssistantAPI(transcribedText, selectedText)
                if not result then
                    toggleMouseIndicator("error")
                    hs.timer.doAfter(1, function() toggleMouseIndicator() end)
                    hs.alert.show("Error: " .. (err or "Unknown"), alertStyle)
                    hs.sound.getByName("Basso"):play()
                    return
                end
                hs.pasteboard.setContents(result)
                hs.timer.usleep(500000)
                hs.eventtap.keyStroke({"cmd"}, "v")
                hs.sound.getByName("Blow"):play()
                toggleMouseIndicator("done")
                hs.timer.doAfter(1, function() toggleMouseIndicator() end)
            end)
        else
            -- If there's selected text but no recording yet
            -- if selectedText then
            --     hs.alert.show("Recording with context...", alertStyle)
            -- end
            startRecording()
        end
    end)
end

local function assistantInteractFromClipboard()
    -- Save original clipboard content
    local originalClipboard = hs.pasteboard.getContents()
    toggleMouseIndicator("processing")
    
    -- Try to copy any selected text
    sendKeystroke({"cmd"}, "c")
    hs.timer.doAfter(0.1, function()  -- Small delay to ensure copy completes
        local newClipboard = hs.pasteboard.getContents()
        
        -- If nothing was selected/copied
        if not newClipboard or newClipboard == "" then
            hs.alert.show("No text selected", alertStyle)
            hs.sound.getByName("Basso"):play()
            return
        end

        -- addToHistory("user", newClipboard)
        
        local result, err = callAssistantAPI(newClipboard)
        if not result then
            toggleMouseIndicator("error")
            hs.timer.doAfter(1, function() toggleMouseIndicator() end)
            hs.alert.show("Error: " .. (err or "Unknown"), alertStyle)
            hs.sound.getByName("Basso"):play()
            return
        end
        
        hs.pasteboard.setContents(result)
        hs.timer.usleep(500000)
        hs.eventtap.keyStroke({"cmd"}, "v")
        hs.sound.getByName("Blow"):play()
        toggleMouseIndicator("done")
        hs.timer.doAfter(1, function() toggleMouseIndicator() end)
    end)
end

-----------------------------------------
-- Shortcut Management
-----------------------------------------
local updateMenuBar
local toggleAutoGrammar
local toggleCondensedMode

toggleAutoGrammar = function()
    autoGrammarAfterTranscribe = not autoGrammarAfterTranscribe
    hs.settings.set("autoGrammarAfterTranscribe", autoGrammarAfterTranscribe)
    updateMenuBar()  -- Add this line
    hs.alert.show("Auto-Grammar: " .. (autoGrammarAfterTranscribe and "ON" or "OFF"), alertStyle)
end

toggleCondensedMode = function()
    condensedMode = not condensedMode
    hs.settings.set("condensedMode", condensedMode)
    updateMenuBar()  -- Add this line
    hs.alert.show("Condensed Mode: " .. (condensedMode and "ON" or "OFF"), alertStyle)
end


updateMenuBar = function()
    if not menuBar then
        menuBar = hs.menubar.new()
        local iconPath = scriptDir .. "icon.png"
        if hs.fs.attributes(iconPath) then
            menuBar:setIcon(iconPath)  -- Just use the path directly
        else
            -- Fallback to emoji if icon file isn't found
            menuBar:setTitle("🤖")
        end
    end
    
    menuBar:setMenu({
        { title = "-= UC AI Assistant =-", disabled = true },
        -- add comand to open the prompt file
        { title = "Edit Grammar Prompt", fn = function()
            hs.task.new("/usr/bin/open", nil, {"-t", promptFile}):start()
        end },
        { title = "Edit Assistant Prompt", fn = function()
            hs.task.new("/usr/bin/open", nil, {"-t", assistantPromptFile}):start()
        end },
        { title = "-" },  -- separator
        { title = "Auto-Grammar: " .. (autoGrammarAfterTranscribe and "✅ ON" or "❌ OFF"), fn = toggleAutoGrammar },
        { title = "Condensed Mode: " .. (condensedMode and "✅ ON" or "❌ OFF") , fn = toggleCondensedMode },
        { title = "-" },  -- separator
        { title = "View Detailed Settings", fn = function()
            local currentSettings = [[
Current Settings:
---------------
Auto-Grammar: ]] .. (autoGrammarAfterTranscribe and "ON" or "OFF") .. [[

Condensed Mode: ]] .. (condensedMode and "ON" or "OFF")
            hs.alert.show(currentSettings, alertStyle, hs.screen.mainScreen(), 5)
        end },
        { title = "-" },  -- separator
        { title = "Configure Shortcuts", fn = function()
            chooseCommandToSetShortcut()
        end }
    })
end

local commands = {
    {
        name = "Grammar Fix",
        settingKey = "grammarShortcut",
        default = {{"alt", "cmd"}, "G"},
        action = grammarFix
    },
    {
        name = "Transcription",
        settingKey = "transcriptionShortcut",
        default = {{"alt", "cmd"}, "K"},
        action = transcriptionToggle
    },
    {
        name = "Edit Grammar Prompt",
        settingKey = "editPromptShortcut",
        default = {{"ctrl", "alt", "cmd"}, "P"},
        action = function()
            hs.task.new("/usr/bin/open", nil, {"-t", promptFile}):start()
        end
    },
    {
        name = "Toggle Auto-Grammar After Transcribe",
        settingKey = "autoGrammarToggle",
        default = {{"ctrl", "alt", "cmd"}, "T"},
        action = toggleAutoGrammar
    },
    {
        name = "Toggle Condensed Mode",
        settingKey = "condensedModeToggle",
        default = {{"ctrl", "alt", "cmd"}, "C"},
        action = toggleCondensedMode
    },
    {
        name = "AI Assistant",
        settingKey = "assistantShortcut",
        default = {{"alt", "cmd"}, "O"},
        action = assistantInteract
    },
    {
        name = "AI Assistant (Clipboard)",
        settingKey = "assistantClipboardShortcut",
        default = {{"alt", "cmd"}, "I"},
        action = assistantInteractFromClipboard
    },
    {
        name = "Edit Assistant Prompt",
        settingKey = "editAssistantPromptShortcut",
        default = {{"ctrl", "alr", "cmd", }, "A"},
        action = function()
            hs.task.new("/usr/bin/open", nil, {"-t", assistantPromptFile}):start()
        end
    },
    {
        name = "View Conversation History",
        settingKey = "viewHistoryShortcut",
        default = {{"ctrl", "alt", "cmd"}, "H"},
        action = function()
            hs.task.new("/usr/local/bin/code", nil, {conversationHistoryFile}):start()
        end
    }
}

local activeHotkeys = {}
local function rebindHotkeys()
    for _, cmd in ipairs(commands) do
        if activeHotkeys[cmd.settingKey] then
            activeHotkeys[cmd.settingKey]:delete()
        end
        local shortcut = hs.settings.get(cmd.settingKey) or cmd.default
        local mods, key = shortcut[1], shortcut[2]
        activeHotkeys[cmd.settingKey] = hs.hotkey.bind(mods, key, cmd.action)
    end
end

local keyListener = nil
local function captureShortcutForCommand(cmd)
    hs.alert.show("Press your desired shortcut...", {textSize = 16})
    if keyListener then keyListener:stop() end
    keyListener = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local mods = event:getFlags()
        local key = event:getKeyCode()
        local modifierNames = {}
        for m, active in pairs(mods) do
            if active then table.insert(modifierNames, m) end
        end
        local keyName = hs.keycodes.map[key]
        if not keyName then
            hs.alert.show("Invalid key. Try again.")
            return false
        end
        hs.settings.set(cmd.settingKey, {modifierNames, keyName})
        hs.alert.show("Shortcut set to " .. table.concat(modifierNames, "+") .. "+" .. keyName, {textSize = 16})
        rebindHotkeys()
        keyListener:stop()
        keyListener = nil
        return true
    end)
    keyListener:start()
end

local function chooseCommandToSetShortcut()
    local choices = {}
    for i, cmd in ipairs(commands) do
        local current = hs.settings.get(cmd.settingKey) or cmd.default
        local mods, key = current[1], current[2]
        table.insert(choices, {
            text = cmd.name,
            subText = "Current: " .. table.concat(mods, "+") .. "+" .. key,
            uuid = tostring(i)
        })
    end
    local chooser = hs.chooser.new(function(choice)
        if not choice then
            hs.alert.show("Shortcut configuration cancelled", alertStyle)
            return
        end
        local idx = tonumber(choice.uuid)
        captureShortcutForCommand(commands[idx])
    end)
    chooser:choices(choices)
    chooser:show()
end



hs.hotkey.bind({"ctrl", "alt", "cmd"}, "S", chooseCommandToSetShortcut)
rebindHotkeys()

-- Initialize menu bar
updateMenuBar()

-- Done
