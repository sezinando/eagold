#property strict
#property version   "0.011"
#property description "EAGOLD - FirstStep, directional trailing, BUY TP and SELL progression state anchor"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.20;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit               = 100;
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";

// SELL progression state.
// The anchor is the actual price of the most recently ACTIVATED SELL.
// It is deliberately not recalculated from arbitrary historical SELLs on every tick.
int    g_sellAnchorTicket = -1;
double g_sellAnchorPrice  = 0.0;


double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

int CountOrders(int type)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder()) continue;
      if(OrderType() == type) count++;
   }
   return(count);
}

int SendPending(int type, double price, string comment)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, Lot, price, 0, 0, 0,
                          comment, MagicNumber, 0, clrNONE);

   if(ticket < 0)
      Print(EA_NAME, " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " error=", GetLastError());
   else
      Print(EA_NAME, " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(Lot, DigitsLots),
            " comment=", comment);

   return(ticket);
}

// FIRST STEP:
// BUY STOP  = ASK + FirstStep
// SELL STOP = BID - FirstStep
void CreateFirstStepOrders()
{
   int total = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(IsEAGOLDOrder()) total++;
   }

   if(total > 0) return;

   RefreshRates();
   double buyPrice  = NormalizePrice(Ask + PointsToPrice(FirstStep));
   double sellPrice = NormalizePrice(Bid - PointsToPrice(FirstStep));

   Print(EA_NAME, " FIRST STEP. BID=", DoubleToString(Bid, Digits),
         " ASK=", DoubleToString(Ask, Digits),
         " FirstStep=", DoubleToString(FirstStep, 0),
         " BUY STOP=", DoubleToString(buyPrice, Digits),
         " SELL STOP=", DoubleToString(sellPrice, Digits));

   SendPending(OP_BUYSTOP, buyPrice, "EAGOLD FIRST STEP BUY");
   SendPending(OP_SELLSTOP, sellPrice, "EAGOLD FIRST STEP SELL");
}

// BUY STOP can only move DOWN.
// It follows a falling ASK while preserving FirstStep distance.
// It NEVER moves back UP.
void TrailBuyStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUYSTOP) continue;

      RefreshRates();
      double desired   = NormalizePrice(Ask + PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = current - desired;
      double trailStep = PointsToPrice(PendingStepTrail);

      if(desired >= current) continue;
      if(movement < trailStep) continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(desired <= Ask + stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " BUY STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      else
         Print(EA_NAME, " BUY STOP TRAIL DOWN. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
   }
}

// SELL STOP directional trailing applies ONLY to the original FIRST STEP SELL STOP.
// Progression SELL STOP orders are fixed at their calculated SmartGrid region
// and MUST NOT be moved by this trailing logic.
void TrailSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;
      if(OrderComment() != "EAGOLD FIRST STEP SELL") continue;

      RefreshRates();
      double desired   = NormalizePrice(Bid - PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = desired - current;
      double trailStep = PointsToPrice(PendingStepTrail);

      if(desired <= current) continue;
      if(movement < trailStep) continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(desired >= Bid - stopLevel) continue;

      ResetLastError();
      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
         Print(EA_NAME, " FIRST STEP SELL STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      else
         Print(EA_NAME, " FIRST STEP SELL STOP TRAIL UP. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
   }
}

// BUY TAKE PROFIT:
// Close each open BUY when BID reaches OpenPrice + TakeProfit.
void ProcessBuyTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      RefreshRates();
      double openPrice = OrderOpenPrice();
      double target    = NormalizePrice(openPrice + PointsToPrice(TakeProfit));

      if(Bid < target) continue;

      int ticket        = OrderTicket();
      double lots       = OrderLots();
      double closePrice = NormalizePrice(Bid);

      ResetLastError();
      if(!OrderClose(ticket, lots, closePrice, 0, clrNONE))
      {
         Print(EA_NAME, " BUY TAKE PROFIT close failed. ticket=", ticket,
               " open=", DoubleToString(openPrice, Digits),
               " target=", DoubleToString(target, Digits),
               " Bid=", DoubleToString(Bid, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " BUY TAKE PROFIT. ticket=", ticket,
               " open=", DoubleToString(openPrice, Digits),
               " target=", DoubleToString(target, Digits),
               " close=", DoubleToString(closePrice, Digits));
      }
   }
}

// Find the most recently activated SELL currently open.
// Ticket is used as the tie-breaker when several SELLs are opened in the same second.
bool FindLatestOpenSell(int &ticket, double &openPrice, datetime &openTime)
{
   ticket   = -1;
   openPrice = 0.0;
   openTime = 0;
   bool found = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      int t = OrderTicket();
      datetime ot = OrderOpenTime();

      if(!found || ot > openTime || (ot == openTime && t > ticket))
      {
         found = true;
         ticket = t;
         openPrice = OrderOpenPrice();
         openTime = ot;
      }
   }

   return(found);
}

// Synchronize the progression anchor with the most recently ACTIVATED SELL.
// This happens only when a new SELL ticket appears, not on every tick.
void UpdateSellAnchor()
{
   int latestTicket = -1;
   double latestPrice = 0.0;
   datetime latestTime = 0;

   if(!FindLatestOpenSell(latestTicket, latestPrice, latestTime))
      return;

   if(latestTicket == g_sellAnchorTicket)
      return;

   g_sellAnchorTicket = latestTicket;
   g_sellAnchorPrice  = latestPrice;

   Print(EA_NAME,
         " SELL ANCHOR UPDATED. ticket=", g_sellAnchorTicket,
         " entry=", DoubleToString(g_sellAnchorPrice, Digits));
}

// SELL PROGRESSION — STRICT RULE:
//
// 1. A SELL must first be ACTIVATED.
// 2. Its actual execution price becomes the anchor.
// 3. The market must move FirstStep points ABOVE that exact anchor.
// 4. ONLY THEN is a new SELL STOP created.
// 5. The new SELL STOP is fixed at anchor + SmartGrid1.
// 6. The progression pending is never trailed.
// 7. Once that pending is activated, its execution price becomes the new anchor.
void ProcessSellProgression()
{
   if(FirstStep <= 0.0 || SmartGrid1 <= 0.0) return;

   // First detect whether a new SELL was actually activated.
   UpdateSellAnchor();

   // Without an actual SELL anchor there is no progression.
   if(g_sellAnchorTicket < 0 || g_sellAnchorPrice <= 0.0)
      return;

   // Never create another progression while one SELL STOP is already pending.
   if(CountOrders(OP_SELLSTOP) > 0)
      return;

   RefreshRates();

   // Use the chart-side BID as the market reference.
   // Distance is explicitly calculated in broker points from the actual SELL entry.
   double distancePoints = (Bid - g_sellAnchorPrice) / Point;
   double triggerPrice   = NormalizePrice(g_sellAnchorPrice + PointsToPrice(FirstStep));

   // STRICT: less than FirstStep means absolutely nothing happens.
   if(distancePoints < FirstStep)
      return;

   // Place the next SELL STOP only after the complete FirstStep distance has been reached.
   double newSellStop = NormalizePrice(g_sellAnchorPrice + PointsToPrice(SmartGrid1));

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newSellStop >= Bid - stopLevel)
   {
      Print(EA_NAME,
            " SELL progression waiting: region too close to BID. anchorTicket=",
            g_sellAnchorTicket,
            " anchor=", DoubleToString(g_sellAnchorPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " distancePoints=", DoubleToString(distancePoints, 1),
            " required=", DoubleToString(FirstStep, 1),
            " trigger=", DoubleToString(triggerPrice, Digits),
            " newStop=", DoubleToString(newSellStop, Digits));
      return;
   }

   Print(EA_NAME,
         " SELL PROGRESSION TRIGGERED. anchorTicket=", g_sellAnchorTicket,
         " anchor=", DoubleToString(g_sellAnchorPrice, Digits),
         " Bid=", DoubleToString(Bid, Digits),
         " distancePoints=", DoubleToString(distancePoints, 1),
         " required=", DoubleToString(FirstStep, 1),
         " trigger=", DoubleToString(triggerPrice, Digits),
         " newSELLSTOP=", DoubleToString(newSellStop, Digits));

   SendPending(OP_SELLSTOP, newSellStop, "EAGOLD SELL PROGRESSION");
}

int OnInit()
{
   Print(EA_NAME, " v0.011 initialized. FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfit=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots));

   // If the EA is attached/restarted while SELLs already exist,
   // establish the anchor from the most recently activated SELL once.
   UpdateSellAnchor();

   CreateFirstStepOrders();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   // Implemented behavior only:
   // 1. Rising price  -> ORIGINAL FIRST STEP SELL STOP may move UP only.
   // 2. Falling price -> BUY STOP may move DOWN only.
   // 3. Open BUY      -> close at TakeProfit.
   // 4. Open SELL + STRICT FirstStep adverse move -> fixed next SELL STOP at SmartGrid1.
   // 5. SELL progression pending orders do NOT trail.
   TrailSellStop();
   TrailBuyStop();
   ProcessBuyTakeProfit();
   ProcessSellProgression();
}
