-- Send a whole message using the UI Program input field and Send/Enter.
-- Works on physical and personal computers. Typing alone does not deliver it.
return {
  init = function()
    state.messages = 0
    term.addInputListener("receive")
    term.write("Ready. Type into Program input, then choose Send.")
  end,
  receive = function(event)
    state.messages = state.messages + 1
    state.last_input = event.userInput
    term.write("Message " .. state.messages .. ": " .. event.userInput)
    disk.writeFile("/last-input.txt", event.userInput)
  end
}
