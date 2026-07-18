-- Unmaps just incase (probably does nothing)
rift.unmap("i", "<A-a>")

-- Maps Alt+a to take me from insert to normal mode
rift.map("i", "<A-a>", "mode:normal")

-- Maps Alt+a to take me from terminal insert to terminal normal
rift.map("t", "<A-a>", "terminal:exit")

-- No glide animation
rift.exec_action("editor:run:set cursorspeed=1.0")

