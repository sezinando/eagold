#property strict
#property version   "0.032"
#property description "EAGOLD - independent BUY and SELL state machines"

input int    MagicNumber              = 1001;
input double Lot                      = 0.01;
input double Multiplier               = 1.10;
input int    DigitsLots               = 2;
input double LotIncrement             = 0.02;
input double MaxOpenLot               = 3.00;
input double TakeProfit               = 5.00;
input double SellProfit               = 30.00;
input double BasketLoss               = 100.00;
input int    SpreadLimit              = 100;
input int    WaitSeconds              = 0;
input double FirstStep                = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail          = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";

// ============================================================
// COMMON UTILITIES
// ============================================================

double PointsToPrice(double points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}

bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

int CountOrdersByType(int type)
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

int SendPending(int type, double price, double lots, string comment)
{
   RefreshRates();

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);
   lots  = NormalizeLot(lots);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0,
                          comment, MagicNumber, 0, clrNONE);

   if(ticket < 0)
   {
      Print(EA_NAME, " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " error=", GetLastError());
   }
   else
   {
      Print(EA_NAME, " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " comment=", comment);
   }

   return(ticket);
}

// ============================================================
// BUY MACHINE
// ============================================================

int BuyLastProcessedCloseTicket = -1;

double BuyNextLot(double previousLot)
{
   return(NormalizeLot(previousLot + LotIncrement));
}

void BuyCreateFirstStep()
{
   if(CountOrdersByType(OP_BUY) > 0) return;
   if(CountOrdersByType(OP_BUYSTOP) > 0) return;

   RefreshRates();
   double price = NormalizePrice(Ask + PointsToPrice(FirstStep));

   SendPending(OP_BUYSTOP, price, NormalizeLot(Lot),
               "EAGOLD FIRST STEP BUY");
}

void BuyTrailPending()
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
      {
         Print(EA_NAME, " BUY MACHINE: BUY STOP modify failed. ticket=",
               OrderTicket(), " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " BUY MACHINE: BUY STOP TRAIL DOWN. ticket=",
               OrderTicket(), " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
      }
   }
}

void BuyTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      if(OrderComment() != "EAGOLD FIRST STEP BUY") continue;

      RefreshRates();
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double bid  = NormalizePrice(Bid);

      ResetLastError();
      if(!OrderClose(ticket, lots, bid, 0, clrNONE))
      {
         Print(EA_NAME, " BUY MACHINE: monetary TAKE PROFIT close failed. ticket=",
               ticket, " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " BUY MACHINE: monetary TAKE PROFIT. ticket=",
               ticket, " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
      }
   }
}

void BuyInitializeCloseTracker()
{
   datetime latestCloseTime = 0;
   int latestTicket = -1;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      datetime closeTime = OrderCloseTime();
      int ticket = OrderTicket();

      if(closeTime > latestCloseTime ||
         (closeTime == latestCloseTime && ticket > latestTicket))
      {
         latestCloseTime = closeTime;
         latestTicket = ticket;
      }
   }

   BuyLastProcessedCloseTicket = latestTicket;
}

void BuyReentryAfterClose()
{
   if(MiniGrid1 <= 0.0) return;

   int latestClosedTicket = -1;
   datetime latestCloseTime = 0;
   double latestClosePrice = 0.0;
   double latestClosedLot = NormalizeLot(Lot);
   bool foundNewClose = false;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      int ticket = OrderTicket();
      datetime closeTime = OrderCloseTime();
      if(ticket == BuyLastProcessedCloseTicket) continue;
      if(closeTime <= 0) continue;

      if(!foundNewClose || closeTime > latestCloseTime ||
         (closeTime == latestCloseTime && ticket > latestClosedTicket))
      {
         foundNewClose = true;
         latestCloseTime = closeTime;
         latestClosedTicket = ticket;
         latestClosePrice = OrderClosePrice();
         latestClosedLot = OrderLots();
      }
   }

   if(!foundNewClose) return;

   BuyLastProcessedCloseTicket = latestClosedTicket;

   if(CountOrdersByType(OP_BUYSTOP) > 0)
   {
      Print(EA_NAME,
            " BUY MACHINE: close detected but BUY STOP already exists. ticket=",
            latestClosedTicket);
      return;
   }

   RefreshRates();
   double newBuyStop = NormalizePrice(Ask + PointsToPrice(MiniGrid1));
   double nextLot = BuyNextLot(latestClosedLot);

   Print(EA_NAME,
         " BUY MACHINE: REENTRY. closedTicket=", latestClosedTicket,
         " closedPrice=", DoubleToString(latestClosePrice, Digits),
         " previousLot=", DoubleToString(latestClosedLot, DigitsLots),
         " nextLot=", DoubleToString(nextLot, DigitsLots),
         " Ask=", DoubleToString(Ask, Digits),
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " newBUYSTOP=", DoubleToString(newBuyStop, Digits));

   SendPending(OP_BUYSTOP, newBuyStop, nextLot,
               "EAGOLD BUY REENTRY MINIGRID1");
}

void BuyMachine()
{
   BuyTrailPending();
   BuyTakeProfit();
   BuyReentryAfterClose();
   BuyCreateFirstStep();
}

// ============================================================
// SELL MACHINE
// ============================================================

double SellNextLot(double previousLot)
{
   return(NormalizeLot((previousLot * Multiplier) + LotIncrement));
}

void SellCreateFirstStep()
{
   if(CountOrdersByType(OP_SELL) > 0) return;
   if(CountOrdersByType(OP_SELLSTOP) > 0) return;

   RefreshRates();
   double price = NormalizePrice(Bid - PointsToPrice(FirstStep));

   SendPending(OP_SELLSTOP, price, NormalizeLot(Lot),
               "EAGOLD FIRST STEP SELL");
}

void SellTrailPending()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;

      // Only FIRST STEP SELL STOP is trailed.
      // SELL PROGRESSION remains fixed at its calculated entry level.
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
      {
         Print(EA_NAME, " SELL MACHINE: FIRST STEP SELL STOP modify failed. ticket=",
               OrderTicket(), " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " SELL MACHINE: FIRST STEP SELL STOP TRAIL UP. ticket=",
               OrderTicket(), " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
      }
   }
}

void SellTakeProfit()
{
   if(TakeProfit <= 0.0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;
      if(OrderComment() != "EAGOLD FIRST STEP SELL") continue;

      RefreshRates();
      double profit = OrderProfit();
      if(profit < TakeProfit) continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double ask  = NormalizePrice(Ask);

      ResetLastError();
      if(!OrderClose(ticket, lots, ask, 0, clrNONE))
      {
         Print(EA_NAME, " SELL MACHINE: monetary TAKE PROFIT close failed. ticket=",
               ticket, " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " SELL MACHINE: monetary TAKE PROFIT. ticket=",
               ticket, " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
      }
   }
}

bool SellGetLatestActivated(double &latestOpen,
                            double &latestLot,
                            int &latestTicket)
{
   latestOpen = 0.0;
   latestLot = NormalizeLot(Lot);
   latestTicket = -1;

   datetime latestTime = 0;
   bool found = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      datetime openTime = OrderOpenTime();
      int ticket = OrderTicket();

      if(!found || openTime > latestTime ||
         (openTime == latestTime && ticket > latestTicket))
      {
         found = true;
         latestTime = openTime;
         latestOpen = OrderOpenPrice();
         latestLot = OrderLots();
         latestTicket = ticket;
      }
   }

   return(found);
}

void SellProgression()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountOrdersByType(OP_SELLSTOP) > 0) return;

   double lastSellPrice = 0.0;
   double lastSellLot = NormalizeLot(Lot);
   int lastSellTicket = -1;

   if(!SellGetLatestActivated(lastSellPrice, lastSellLot, lastSellTicket))
      return;

   RefreshRates();

   // STEP 1: price must first travel 2 x SmartGrid1 upward
   // from the LAST SELL ACTUALLY ACTIVATED.
   double triggerPrice = NormalizePrice(
      lastSellPrice + PointsToPrice(2.0 * SmartGrid1));

   if(Bid < triggerPrice) return;

   // STEP 2: once the 2 x SmartGrid1 level is reached,
   // the new SELL STOP is positioned at LAST SELL + SmartGrid1.
   // Therefore the pending entry is one SmartGrid1 below the
   // price level that triggered its creation.
   double newSellStop = NormalizePrice(
      lastSellPrice + PointsToPrice(SmartGrid1));

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(newSellStop >= Bid - stopLevel) return;

   double nextLot = SellNextLot(lastSellLot);

   Print(EA_NAME,
         " SELL MACHINE: PROGRESSION TRIGGERED. lastTicket=", lastSellTicket,
         " lastSell=", DoubleToString(lastSellPrice, Digits),
         " lastLot=", DoubleToString(lastSellLot, DigitsLots),
         " multiplier=", DoubleToString(Multiplier, 2),
         " increment=", DoubleToString(LotIncrement, DigitsLots),
         " nextLot=", DoubleToString(nextLot, DigitsLots),
         " Bid=", DoubleToString(Bid, Digits),
         " triggerDistance=", DoubleToString(2.0 * SmartGrid1, 0),
         " triggerPrice=", DoubleToString(triggerPrice, Digits),
         " entryDistance=", DoubleToString(SmartGrid1, 0),
         " newSELLSTOP=", DoubleToString(newSellStop, Digits));

   // Progression pending is fixed. It is NOT trailed by FirstStep.
   SendPending(OP_SELLSTOP, newSellStop, nextLot,
               "EAGOLD SELL PROGRESSION");
}

void SellMachine()
{
   SellTrailPending();
   SellTakeProfit();
   SellProgression();
   SellCreateFirstStep();
}

// ============================================================
// EA LIFECYCLE
// ============================================================

int OnInit()
{
   Print(EA_NAME, " v0.032 initialized.",
         " BUY and SELL are independent machines.",
         " FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfitMoney=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " SELL trigger=", DoubleToString(2.0 * SmartGrid1, 0),
         " SELL entry offset=", DoubleToString(SmartGrid1, 0),
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots),
         " LotIncrement=", DoubleToString(LotIncrement, DigitsLots),
         " MaxOpenLot=", DoubleToString(MaxOpenLot, DigitsLots),
         " SELL Multiplier=", DoubleToString(Multiplier, 2));

   BuyInitializeCloseTracker();

   BuyCreateFirstStep();
   SellCreateFirstStep();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   // Two independent state machines. Neither machine controls the other.
   BuyMachine();
   SellMachine();
}
