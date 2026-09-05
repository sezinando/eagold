#property strict
#property version   "0.009"
#property description "EAGOLD - FirstStep, directional trailing, BUY TP and SELL progression trigger fix"

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
            " lot=", DoubleToString(Lot, DigitsLots));

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
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
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

// Return the most recently activated SELL.
// Ticket number is used as the tie-breaker when several SELLs are opened
// within the same second, which is common in fast backtests.
bool GetLatestSell(double &latestSellOpen, int &latestSellTicket)
{
   latestSellOpen   = 0.0;
   latestSellTicket = -1;
   bool foundSell = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      int ticket = OrderTicket();

      if(!foundSell ||
         OrderOpenTime() > OrderOpenTimeOfTicket(latestSellTicket) ||
         (OrderOpenTime() == OrderOpenTimeOfTicket(latestSellTicket) && ticket > latestSellTicket))
      {
         foundSell = true;
         latestSellOpen = OrderOpenPrice();
         latestSellTicket = ticket;
      }
   }

   return(foundSell);
}

// Helper used only to compare SELL open times safely.
datetime OrderOpenTimeOfTicket(int ticket)
{
   if(ticket < 0) return(0);
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return(0);
   return(OrderOpenTime());
}

// SELL PROGRESSION:
// A new progression SELL STOP may be created ONLY after the price has moved
// FirstStep points AGAINST THE MOST RECENTLY ACTIVATED SELL.
// The reference is the actual open price of that SELL.
// The new SELL STOP is then fixed at latest SELL open + SmartGrid1.
void ProcessSellProgression()
{
   if(FirstStep <= 0.0 || SmartGrid1 <= 0.0) return;

   // Never create another progression while one is already pending.
   if(CountOrders(OP_SELLSTOP) > 0)
      return;

   double latestSellOpen = 0.0;
   int latestSellTicket = -1;

   if(!GetLatestSell(latestSellOpen, latestSellTicket))
      return;

   RefreshRates();

   // For a SELL, adverse movement is an increase in BID.
   // The trigger is EXACTLY FirstStep above the actual latest SELL entry.
   double triggerPrice = NormalizePrice(latestSellOpen + PointsToPrice(FirstStep));

   if(Bid < triggerPrice)
      return;

   // Only after the trigger has been reached do we place the next SELL STOP.
   double newSellStop = NormalizePrice(latestSellOpen + PointsToPrice(SmartGrid1));

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newSellStop >= Bid - stopLevel)
   {
      Print(EA_NAME,
            " SELL progression waiting: new SELL STOP too close to BID. latestTicket=",
            latestSellTicket,
            " latestSell=", DoubleToString(latestSellOpen, Digits),
            " trigger=", DoubleToString(triggerPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " newStop=", DoubleToString(newSellStop, Digits));
      return;
   }

   Print(EA_NAME,
         " SELL PROGRESSION TRIGGERED. latestTicket=", latestSellTicket,
         " latestSell=", DoubleToString(latestSellOpen, Digits),
         " Bid=", DoubleToString(Bid, Digits),
         " trigger=", DoubleToString(triggerPrice, Digits),
         " distance=", DoubleToString((Bid - latestSellOpen) / Point, 1),
         " newSELLSTOP=", DoubleToString(newSellStop, Digits));

   SendPending(OP_SELLSTOP, newSellStop, "EAGOLD SELL PROGRESSION");
}

int OnInit()
{
   Print(EA_NAME, " v0.009 initialized. FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfit=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots));

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
   // 4. Open SELL + FirstStep adverse move -> fixed next SELL STOP at SmartGrid1.
   // 5. SELL progression pending orders do NOT trail.
   TrailSellStop();
   TrailBuyStop();
   ProcessBuyTakeProfit();
   ProcessSellProgression();
}
