-- This projects ports the excellent tutorial found here to Mote:
-- https://codeincomplete.com/posts/tiny-platformer/
--
-- This example extends the previous platformer project to include
-- sound effects, background music, and gamepad input.
--

--tuning parameters for player input

STARTING_MAP = "level1"
GRAVITY = 1.2
MAX_SPEED = { x = 3.4375, y = 6.3 }
LINEAR_ACCELERATION = 0.625 -- how fast the player accelerates when walking
FRICTION = 2 
JUMP_IMPULSE = 25
FALLING_FRICTION_SCALE = 0.5
FALLING_ACCELERATION_SCALE = 0.5
SETTLE_TOLERANCE = 0.11 -- higher number indicates max penetration for player to snap to grid when coming to a stop.

DEFAULT_PLAYER_START = {x = 1, y = 1}

-- counts the number of times Update() has been called. Used only for animating the alpha on the treasures.
frame = 0

-- scales the default abilities of monsters.
monsterScale = 0.3

-- only create a window the first time we load a map
windowCreated = false

-- before loading a level, we draw over previous level
shouldClearBackground = false

-- helper functions

-- returns the tile index for the given x y coordinates (in tile space, where 1 unit = 1 tile)
function getCell(x, y)
    return map.tiles[1][(x + (y * map.width)) + 1] -- +1 because of lua array indexing
end

-- initializes player properties for the start of a new map.
function SetPlayer(actor, x, y)
    actor.x = x
    actor.y = y
    actor.left = false
    actor.right = false
    actor.jump = false
    actor.jumping = false
    actor.falling = false
    actor.gravity = 1.0
    actor.velocity = { x = 0, y = 0 }
    actor.acceleration = { x = 0, y = 0 }
    actor.friction = FRICTION
    actor.linearAcceleration = LINEAR_ACCELERATION
    actor.maxSpeedX = MAX_SPEED.x
    actor.maxSpeedY = MAX_SPEED.y
    actor.jumpImpulse =  JUMP_IMPULSE
    actor.monster = false
end

-- initializes an enemy for the start of a new map.
function SetMonster(actor, x, y)
    actor.monster = true
    actor.x = x
    actor.y = y
    actor.jump = false
    actor.jumping = false
    actor.falling = false
    actor.velocity = { x = 0, y = 0 }
    actor.acceleration = { x = 0, y = 0 }
            
    -- if actor object already has a property
    -- read from the tmx file, it is already set.
    -- if it is nil, set it to a sensible default.
    
    if actor.left == nil then
        actor.left = true
    end
        
    if actor.right == nil then
        actor.right = false
    end
    
    if actor.maxSpeedX == nil then
        actor.maxSpeedX = MAX_SPEED.x * monsterScale
    end
    
    if actor.maxSpeedY == nil then
        actor.maxSpeedY = MAX_SPEED.y * monsterScale
    end
    
    if actor.gravity == nil then
        actor.gravity = 1
    end
    
    if actor.friction == nil then
        actor.friction = FRICTION
    end
    
    if actor.linearAcceleration == nil then
        actor.linearAcceleration = LINEAR_ACCELERATION * monsterScale
    end
    
    if actor.jumpImpulse == nil then
        actor.jumpImpulse =  JUMP_IMPULSE * monsterScale
    end
end

-- read input from the player.
function UpdatePlayerInput()
    player.left = false
    player.right = false
    player.jump = false

    local moveX = GetInputX()
        
    if IsKeyDown(SDL_SCANCODE_LEFT) or (moveX < 0) == true then player.left = true end
    if IsKeyDown(SDL_SCANCODE_RIGHT) or (moveX > 0) == true then player.right = true end
    if IsKeyDown(SDL_SCANCODE_SPACE)  or (controller_0_button_0 == 1) then player.jump = true end
end

--updates the physics of actors such as the player and enemies.
function UpdateActor(actor)
    local wasLeft = actor.velocity.x < 0
    local wasRight = actor.velocity.x > 0
    local falling = actor.falling
              
    local friction = actor.friction * Pick(falling, FALLING_FRICTION_SCALE, 1.0)
    local acceleration = actor.linearAcceleration * Pick(falling, FALLING_ACCELERATION_SCALE, 1.0)
    
    actor.acceleration.x = 0
    actor.acceleration.y = GRAVITY * actor.gravity
    
    if actor.left then actor.acceleration.x = actor.acceleration.x - acceleration
    elseif wasLeft then actor.acceleration.x = actor.acceleration.x + friction end
    
    if actor.right then actor.acceleration.x = actor.acceleration.x + acceleration
    elseif wasRight then actor.acceleration.x = actor.acceleration.x - friction end
    
    --start jumping?
    if actor.jump and not actor.jumping and not falling then
        actor.acceleration.y = actor.acceleration.y - actor.jumpImpulse
        actor.jumping = true
        if actor == player then PlaySound(jumpSfx) end
    end
    
    local dt = GetFrameTime() / 100.0
    
    actor.x = actor.x + actor.velocity.x * dt
    actor.y = actor.y + actor.velocity.y * dt
    actor.velocity.x = Clamp(actor.velocity.x + actor.acceleration.x * dt, -actor.maxSpeedX, actor.maxSpeedX)
    actor.velocity.y = Clamp(actor.velocity.y + actor.acceleration.y * dt, -actor.maxSpeedY, actor.maxSpeedY)
    
    --clamp x velocity to prevent jiggle when changing directions
    if (wasLeft and actor.velocity.x > 0) or (wasRight and actor.velocity.x < 0) then 
        actor.velocity.x = 0
    end
    
    local tileX = math.floor(actor.x)
    local tileY = math.floor(actor.y) 
    
    -- how deeply are we penetrating other tiles?
    nx = math.fmod(actor.x, 1)
    ny = math.fmod(actor.y, 1)
    
    local cell = getCell(tileX, tileY)
    local cellRight = getCell(tileX + 1, tileY)
    local cellDown = getCell(tileX, tileY + 1)
    local cellDiag = getCell(tileX + 1, tileY + 1)
    
    if Contains(map.walkable, cell) then cell = nil end
    if Contains(map.walkable, cellRight) then cellRight = nil end
    if Contains(map.walkable, cellDown) then cellDown = nil end
    if Contains(map.walkable, cellDiag) then cellDiag = nil end
            
    if actor.velocity.y > 0 then
        if (cellDown and not cell) or (cellDiag and not cellRight and nx > 0) then
            if actor.jumping then
                if actor == player then PlaySound(landSfx) end
            end
            actor.y = tileY
            actor.velocity.y = 0
            actor.falling = false
            actor.jumping = false
            ny = 0
        end
    elseif actor.velocity.y < 0 then
        if (cell and not cellDown) or (cellRight and not cellDiag and nx > 0) then
            actor.y = tileY + 1
            actor.velocity.y = 0
            cell = cellDown
            cellRight = cellDiag
            ny = 0
            if actor.jumping then
                if actor == player then PlaySound(landSfx) end
            end
        end
    end
    
    if actor.velocity.x > 0 then
        if (cellRight and not cell) or (cellDiag and not cellDown and ny > 0) then
            actor.x = tileX
            actor.velocity.x = 0
        end
    elseif actor.velocity.x < 0 then
        if (cell and not cellRight) or (cellDown and not cellDiag and ny > 0) then
            actor.x = tileX + 1
            actor.velocity.x = 0
        end
    end
       
    actor.falling = not (cellDown or (nx > 0 and cellDiag))
    
    -- let the actor tend to settle aligned to the grid so that it can fit through one-tile holes.
    if actor.velocity.x == 0 and actor.velocity.y == 0 and math.fmod(actor.x, 1) < SETTLE_TOLERANCE then
        actor.x = math.floor(actor.x)
    end
    
    -- bounce monster if it is at a platform edge.
    if actor.monster then
        if actor.left and (cell or not cellDown) then
            actor.left = false
            actor.right = true
        elseif actor.right and (cellRight or not cellDiag) then
            actor.left = true
            actor.right = false
        end
    end
end

-- tests whether player is overlapping a treasure. If so, collect the treasure.
function UpdateTreasures()
    if treasures ~= nil then
        for i = #treasures, 1, -1 do
            if BoxesOverlapWH(treasures[i].x, treasures[i].y, 1, 1, player.x, player.y, 1, 1) then
                table.remove(treasures, i)
                player.treasures = player.treasures + 1
                PlaySound(lootSfx)
            end
        end
    end
end

-- tests whether player is overlapping an exit. If so, loads the next level.
function UpdateExits()
    if map.exit ~= nil then
        for i = #map.exit, 1, -1 do
            if BoxesOverlapWH(map.exit[i].x, map.exit[i].y, 1, 1, player.x, player.y, 1, 1) then
                PlaySound(exitSfx)
                LoadMap(map.exit[i].map)
                shouldClearBackground = true
                return
            end
        end
    end
end

-- tests whether player has defeated monster or a monster
-- has defeated the player.
function UpdateMonsters()
    if monsters ~= nil then
        for i = #monsters, 1, -1 do
            local removed = false
        
            if BoxesOverlapWH(monsters[i].x, monsters[i].y, 1, 1, player.x, player.y, 1, 1) then
                if (player.velocity.y > 0) and (monsters[i].y - player.y > 0.4) == true then
                    table.remove(monsters, i)
                    player.enemyDefeats = player.enemyDefeats + 1
                    removed = true
                    PlaySound(defeatEnemySfx)
                else
                    player.x = map.playerStart[1].x
                    player.y = map.playerStart[1].y
                    player.velocity.x = 0
                    player.velocity.y = 0
                    player.defeats = player.defeats + 1
                    PlaySound(defeatedSfx)
                end
            end
            
            if not removed then
                UpdateActor(monsters[i])
            end
        end
    end
end

-- draw exits to the screen.
function DrawExits()
    SetDrawColor(15, 163, 172, 255)
    
    for i = 1, #map.exit do
        FillRect(map.exit[i].x * map.tileSize, map.exit[i].y * map.tileSize,  map.tileSize, map.tileSize)
    end
end

-- draw the tiles from the tmx file.
function DrawWorld()
    for y = 0, map.height - 1 do
        for x = 0, map.width - 1 do
            local tileImageIndex = map.tiles[1][(x + y * map.width) + 1]
            DrawImageFrame(tileImage, x * map.tileSize, y * map.tileSize, map.tileSize, map.tileSize, tileImageIndex - 1, 0, 1)
        end
    end
end

-- draw player to the screen.
function DrawPlayer()
    SetDrawColor(255, 255, 255, 255)
    FillRect(player.x * map.tileSize, player.y * map.tileSize, map.tileSize, map.tileSize)
end

-- draw the enemies to the screen.
function DrawMonsters()
    if monsters ~= nil then
        SetDrawColor(24, 24, 24, 255)
        
        for i = 1, #monsters do
            FillRect(monsters[i].x * map.tileSize, monsters[i].y * map.tileSize,  map.tileSize, map.tileSize)
        end
    end
end

-- draw the treasures to the screen. Ramp their
-- alpha based on how many frames have elapsed so 
-- that treasures appear to pulsate.
function DrawTreasures()
    if treasures ~= nil then
        local duration = 60
        local half = duration / 2
        local pulse = frame % duration
        
        local glow = 0
        if pulse < half then
            glow = pulse / half
        else
            glow = 1 - (pulse - half) / half;
        end
        
        local alpha = math.floor( glow * 255 )    
          
        SetDrawColor(243, 246, 19, alpha)
        
        for i = 1, #treasures do
            FillRect(treasures[i].x * map.tileSize, treasures[i].y * map.tileSize,  map.tileSize, map.tileSize)
        end
    end
end

-- create a new player object, but copy
-- player metrics such as num treasures found
-- from previous instance.
function RefreshPlayer()
    local numEnemyDefeats = 0
    local numTreasures = 0
    local numDefeats = 0
    
    if player ~= nil then
        numEnemyDefeats = player.enemyDefeats
        numTreasures = player.treasures
        numDefeats = player.defeats
    end
    
    player = {}
    
    player.enemyDefeats = numEnemyDefeats
    player.treasures = numTreasures
    player.defeats = numDefeats
end

-- start a new level using the specified tmx file.
-- file name should be passed with no .tmx extension.
function LoadMap(mapFile)
    monsters = nil
    treasures = nil
    map = nil
    
    LoadTmxFile(assetDirectory .. "maps/" .. mapFile .. ".tmx")
    map.walkable = {1, 2} --indices of tiles that the player and other actors can walk through.
    
    RefreshPlayer()
    
    -- note that since the window is created once,
    -- all maps will need to use this resolution unless
    -- Mote is extended to resize.
    if not windowCreated then
        CreateWindow(map.width * map.tileSize, map.height * map.tileSize)
        
        font = LoadFont("fonts/8_bit_pusab.ttf", 12)  

        jumpSfx = LoadSound("sfx/shoot.wav")
        landSfx = LoadSound("sfx/bounce.wav")
        lootSfx = LoadSound("sfx/happy.wav")
        defeatEnemySfx = LoadSound("sfx/explosion.wav")
        defeatedSfx = LoadSound("sfx/sad.wav")
        exitSfx = LoadSound("sfx/spawn.wav")
               
        windowCreated = true
    end
    
    StopMusic()
    if map.music ~= nil then
        local music = LoadMusic("music/" .. map.music .. ".ogg")
        PlayMusic(music)
    end
    
    tileImage = LoadImage(map.tileAtlas)
    SetWindowTitle("platformer 4: " .. mapFile)
            
    -- create a start point if the level file does not
    -- define one.
    if (map.playerStart == nil or map.playerStart[1] == nil) then
        map.playerStart = {}
        map.playerStart[1] = {}
        map.playerStart[1].x = DEFAULT_PLAYER_START.x
        map.playerStart[1].y = DEFAULT_PLAYER_START.y
    end
    
    SetPlayer(player, map.playerStart[1].x, map.playerStart[1].y)
    
    -- redirect names from tmx to names that make sense for our script.
    monsters = map.enemy
    treasures = map.treasure
    
    if monsters ~= nil then
        for i = 1, #monsters do
            SetMonster(monsters[i], monsters[i].x, monsters[i].y)
        end
    end
end

-- core functions

function Start()
    LoadMap(STARTING_MAP)
end

function Update()
    frame = frame + 1

    UpdatePlayerInput()
    UpdateActor(player)
    UpdateTreasures()
    UpdateMonsters()
    
    --always want to do this last in the frame
    --because it can cause a map load.
    UpdateExits()
end

function Draw()
    if shouldClearBackground == true then
        ClearScreen(0, 0, 0)
        shouldClearBackground = false
    end

    DrawWorld()
    DrawExits()
    DrawTreasures()
    DrawMonsters()
    DrawPlayer()
    DrawText("E: " .. player.enemyDefeats .. "  T: " .. player.treasures .. "  D: " .. player.defeats, 8, 9, font, 255, 255, 255)
end