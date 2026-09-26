local CHECKS = {}
local function check(ok, what) table.insert(CHECKS, (ok and "PASS " or "FAIL ") .. what) print((ok and "  [ok] " or "  [FAIL] ") .. what) return ok end
local function srv(n) return mockRequire(SERVER_SCRIPT:FindFirstChild(n)) end
runMain(function()
	runScript(SERVER_SCRIPT, MAIN_CTX)
	task.wait(1)
	local C = mockRequire(REPLICATED.Shared.Constants)
	local PD, E = srv("PlayerDataService"), srv("EconomyService")
	local MPS = MarketplaceService
	local prompted = {}
	rawset(MPS, "PromptProductPurchase", function(_, p, id) if type(id) ~= "number" then error("PromptProductPurchase id must be number", 2) end table.insert(prompted, { p, id }) end)
	check(type(MPS.ProcessReceipt) == "function", "ProcessReceipt is set")
	local p1 = addPlayer("Malachi")
	task.wait(2)
	local d = PD:getData(p1)
	local cash0 = d.cash
	local pk = C.ROBUX_PACKS[1]
	local GR, NY = Enum.ProductPurchaseDecision.PurchaseGranted, Enum.ProductPurchaseDecision.NotProcessedYet
	local rc = { PurchaseId = "PUR-1", ProductId = pk.productId, PlayerId = p1.UserId, CurrencySpent = pk.robux, PlaceIdWherePurchased = 0 }
	local r = MPS.ProcessReceipt(rc)
	check(r == GR and PD:getData(p1).cash == cash0 + pk.cash, "first receipt granted, +" .. pk.cash .. " (" .. tostring(r) .. ", cash " .. PD:getData(p1).cash .. ")")
	local store = DataStoreService:GetDataStore("HeistCrewPlayerData_v1")
	local saved = store._data["Player_" .. p1.UserId]
	check(saved and saved.robuxPurchases and saved.robuxPurchases["PUR-1"] ~= nil, "purchase id saved to the DataStore")
	local r2 = MPS.ProcessReceipt(rc)
	check(r2 == GR and PD:getData(p1).cash == cash0 + pk.cash, "duplicate PurchaseId → granted, no second payout (cash " .. PD:getData(p1).cash .. ")")
	local r3 = MPS.ProcessReceipt({ PurchaseId = "PUR-X", ProductId = 42, PlayerId = p1.UserId })
	check(r3 == NY, "unknown product → NotProcessedYet")
	local r4 = MPS.ProcessReceipt({ PurchaseId = "PUR-Y", ProductId = pk.productId, PlayerId = 999999 })
	check(r4 == NY, "player not in server → NotProcessedYet")
	-- concurrent duplicate: make the save yield
	local realSet = store.SetAsync
	store.SetAsync = function(s, k, v) task.wait(1) return realSet(s, k, v) end
	local res = {}
	local rcB = { PurchaseId = "PUR-2", ProductId = C.ROBUX_PACKS[2].productId, PlayerId = p1.UserId }
	task.spawn(function() res[1] = MPS.ProcessReceipt(rcB) end)
	task.wait(0.1)
	res[2] = MPS.ProcessReceipt(rcB)
	task.wait(2)
	store.SetAsync = realSet
	check(res[1] == GR and res[2] == NY and PD:getData(p1).cash == cash0 + pk.cash + C.ROBUX_PACKS[2].cash, "same id twice at once → one granted, one NotProcessedYet, paid once")
	-- save fails in a live server → NotProcessedYet, retry pays nothing extra
	local realStudio = RunService.IsStudio
	rawset(RunService, "IsStudio", function() return false end)
	store.SetAsync = function() error("DataStore down") end
	local cashA = PD:getData(p1).cash
	local rcC = { PurchaseId = "PUR-3", ProductId = pk.productId, PlayerId = p1.UserId }
	local r5 = MPS.ProcessReceipt(rcC)
	check(r5 == NY and PD:getData(p1).cash == cashA + pk.cash, "save failed (live) → NotProcessedYet (cash applied in memory once)")
	store.SetAsync = realSet
	local r6 = MPS.ProcessReceipt(rcC)
	check(r6 == GR and PD:getData(p1).cash == cashA + pk.cash, "retry after save recovers → granted, no double pay")
	rawset(RunService, "IsStudio", realStudio)
	-- save not loaded → NotProcessedYet
	local realGet = store.GetAsync
	store.GetAsync = function() error("DataStore read failed") end
	local p2 = addPlayer("Broken")
	task.wait(8)
	store.GetAsync = realGet
	check(PD:loadFailed(p2), "p2 load failed (simulated)")
	local r7 = MPS.ProcessReceipt({ PurchaseId = "PUR-4", ProductId = pk.productId, PlayerId = p2.UserId })
	check(r7 == NY, "save not loaded → NotProcessedYet (" .. tostring(r7) .. ")")
	-- daily reward status.saveFailed
	local dr = REPLICATED.Remotes.DailyReward
	local st = dr.OnServerInvoke(p2, "status")
	check(st.saveFailed == true, "DailyReward status.saveFailed=true for a failed load")
	check(dr.OnServerInvoke(p1, "status").saveFailed == false, "DailyReward status.saveFailed=false normally")
	-- ShopService robux actions
	local shopRF = REPLICATED.Remotes.ShopAction
	local gs = shopRF.OnServerInvoke(p1, "getState", {})
	check(#gs.state.robuxPacks == #C.ROBUX_PACKS and gs.state.robuxPacks[1].available == true, "getState robuxPacks (" .. #gs.state.robuxPacks .. ", available=" .. tostring(gs.state.robuxPacks[1].available) .. ")")
	local b = shopRF.OnServerInvoke(p1, "buyRobuxPack", { id = "medium" })
	check(b.ok and prompted[1] and prompted[1][2] == C.ROBUX_PACKS[2].productId, "buyRobuxPack opens the product prompt (" .. tostring(prompted[1] and prompted[1][2]) .. ")")
	local b2 = shopRF.OnServerInvoke(p1, "buyRobuxPack", { id = "nope" })
	check(not b2.ok, "buyRobuxPack unknown id refused")
	check(shopRF.OnServerInvoke(p1, "buyMask", { id = "Nope" }).ok == false, "buyMask unknown refused")
	check(shopRF.OnServerInvoke(p1, "equipMask", { id = "Cyber" }).ok == false, "equipMask not owned refused")
	PD:setCash(p1, 10) print("   cash now", PD:getData(p1).cash)
	check(shopRF.OnServerInvoke(p1, "buyMask", { id = "Cyber" }).ok == false, "buyMask too poor refused")
	check(shopRF.OnServerInvoke(p1, "buyCosmetic", { id = "BagSteel" }).ok == false, "buyCosmetic too poor refused")
	check(shopRF.OnServerInvoke(p1, "equipCosmetic", { id = "BagSteel" }).ok == false, "equipCosmetic not owned refused")
	check(shopRF.OnServerInvoke(p1, "bogus", {}).ok == false, "unknown action refused")
	check(shopRF.OnServerInvoke(p1, "getState", "notatable").ok == true, "getState with junk payload ok")
	local fails = 0
	for _, c in ipairs(CHECKS) do if c:sub(1, 4) == "FAIL" then fails += 1 end end
	print(string.format("%d checks, %d failed", #CHECKS, fails))
end, 120)
report()
