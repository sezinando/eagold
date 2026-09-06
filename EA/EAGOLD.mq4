#property strict
#property version   "0.019"
#property description "EAGOLD - independent fixed lot progression"

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

// Last BUY history ticket already processed by the reentry logic.
int LastProcessedBuyCloseTicket = -1;

double PointsToPrice(double points){ return(points * Point); }
double NormalizePrice(double price){ return(NormalizeDouble(price, Digits)); }

double NormalizeLot(double lot)
{
   if(lot < Lot) lot = Lot;
   if(MaxOpenLot > 0.0 && lot > MaxOpenLot) lot = MaxOpenLot;
   return(NormalizeDouble(lot, DigitsLots));
}

double NextLot(double previousLot)
{
   double next = previousLot + LotIncrement;
   return(NormalizeLot(next));
}

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

int SendPending(int type, double price, double lots, string comment)
{
   RefreshRates();
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);
   lots = NormalizeLot(lots);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel) return(-1);
   if(type == OP_SELLSTOP && price >= Bid - stopLevel) return(-1);

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, price, 0, 0, 0,
                          comment, MagicNumber, 0, clrNONE);

   if(ticket < 0)
      Print(EA_NAME, " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots),
            " error=", GetLastError());
   else
      Print(EA_NAME, " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(lots, DigitsLots));

   return(ticket);
}

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

   SendPending(OP_BUYSTOP, buyPrice, NormalizeLot(Lot), "EAGOLD FIRST STEP BUY");
   SendPending(OP_SELLSTOP, sellPrice, NormalizeLot(Lot), "EAGOLD FIRST STEP SELL");
}

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

void TrailSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP) continue;

      string comment = OrderComment();
      if(comment != "EAGOLD FIRST STEP SELL" &&
         comment != "EAGOLD SELL PROGRESSION")
         continue;

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
         Print(EA_NAME, " SELL STOP modify failed. ticket=", OrderTicket(),
               " comment=", comment,
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      else
         Print(EA_NAME, " SELL STOP TRAIL UP. ticket=", OrderTicket(),
               " comment=", comment,
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
   }
}

void ProcessBuyTakeProfit()
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

      int ticket  = OrderTicket();
      double lots = OrderLots();
      double bid  = NormalizePrice(Bid);

      ResetLastError();
      if(!OrderClose(ticket, lots, bid, 0, clrNONE))
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      else
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
   }
}

void ProcessSellTakeProfit()
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

      int ticket  = OrderTicket();
      double lots = OrderLots();
      double ask  = NormalizePrice(Ask);

      ResetLastError();
      if(!OrderClose(ticket, lots, ask, 0, clrNONE))
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " error=", GetLastError());
      else
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2));
   }
}

bool GetLatestSell(double &latestSellOpen, double &latestSellLot, int &latestSellTicket)
{
   latestSellOpen   = 0.0;
   latestSellLot    = NormalizeLot(Lot);
   latestSellTicket = -1;
   datetime latestSellTime = 0;
   bool foundSell = false;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_SELL) continue;

      datetime openTime = OrderOpenTime();
      int ticket = OrderTicket();

      if(!foundSell ||
         openTime > latestSellTime ||
         (openTime == latestSellTime && ticket > latestSellTicket))
      {
         foundSell = true;
         latestSellTime = openTime;
         latestSellOpen = OrderOpenPrice();
         latestSellLot = OrderLots();
         latestSellTicket = ticket;
      }
   }

   return(foundSell);
}

// SELL PROGRESSION:
// The latest activated SELL is the reference (LastSell).
// A progression SELL STOP is created only when price reaches
// LastSell + 2 x SmartGrid1.
// The progression lot is the latest SELL lot + LotIncrement,
// limited by MaxOpenLot.
void ProcessSellProgression()
{
   if(SmartGrid1 <= 0.0) return;
   if(CountOrders(OP_SELLSTOP) > 0) return;

   double latestSellOpen = 0.0;
   double latestSellLot = NormalizeLot(Lot);
   int latestSellTicket = -1;

   if(!GetLatestSell(latestSellOpen, latestSellLot, latestSellTicket)) return;

   RefreshRates();

   double triggerDistance = PointsToPrice(2.0 * SmartGrid1);
   double triggerPrice = NormalizePrice(latestSellOpen + triggerDistance);

   if(Bid < triggerPrice) return;

   double newSellStop = triggerPrice;
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(newSellStop >= Bid - stopLevel)
      return;

   double nextSellLot = NextLot(latestSellLot);

   Print(EA_NAME,
         " SELL PROGRESSION TRIGGERED. latestTicket=", latestSellTicket,
         " latestSell=", DoubleToString(latestSellOpen, Digits),
         " latestLot=", DoubleToString(latestSellLot, DigitsLots),
         " nextLot=", DoubleToString(nextSellLot, DigitsLots),
         " Bid=", DoubleToString(Bid, Digits),
         " triggerDistance=", DoubleToString(2.0 * SmartGrid1, 0),
         " triggerPrice=", DoubleToString(triggerPrice, Digits),
         " newSELLSTOP=", DoubleToString(newSellStop, Digits));

   SendPending(OP_SELLSTOP, newSellStop, nextSellLot, "EAGOLD SELL PROGRESSION");
}

void InitializeBuyCloseTracker()
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

   LastProcessedBuyCloseTicket = latestTicket;
}

// Find the most recent BUY closure and its lot. This is the BUY engine's
// progression reference, independent of the SELL engine.
bool GetLatestClosedBuy(double &latestLot, int &latestTicket, datetime &latestCloseTime)
{
   latestLot = NormalizeLot(Lot);
   latestTicket = -1;
   latestCloseTime = 0;
   bool found = false;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;
      if(OrderCloseTime() <= 0) continue;

      datetime closeTime = OrderCloseTime();
      int ticket = OrderTicket();

      if(!found ||
         closeTime > latestCloseTime ||
         (closeTime == latestCloseTime && ticket > latestTicket))
      {
         found = true;
         latestCloseTime = closeTime;
         latestTicket = ticket;
         latestLot = OrderLots();
      }
   }

   return(found);
}

// BUY REENTRY:
// When a BUY or BUY basket is closed, immediately create one BUY STOP
// at MiniGrid1 points above the current ASK.
// BUY lot progression is independent from SELL:
// next BUY lot = last closed BUY lot + LotIncrement, capped at MaxOpenLot.
void ProcessBuyReentryAfterClose()
{
   if(MiniGrid1 <= 0.0) return;

   int latestClosedTicket = -1;
   datetime latestCloseTime = 0;
   double latestClosePrice = 0.0;
   double latestClosedBuyLot = NormalizeLot(Lot);
   bool foundNewClose = false;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEAGOLDOrder() || OrderType() != OP_BUY) continue;

      int ticket = OrderTicket();
      datetime closeTime = OrderCloseTime();

      if(ticket == LastProcessedBuyCloseTicket) continue;
      if(closeTime <= 0) continue;

      if(!foundNewClose ||
         closeTime > latestCloseTime ||
         (closeTime == latestCloseTime && ticket > latestClosedTicket))
      {
         foundNewClose = true;
         latestCloseTime = closeTime;
         latestClosedTicket = ticket;
         latestClosePrice = OrderClosePrice();
         latestClosedBuyLot = OrderLots();
      }
   }

   if(!foundNewClose) return;

   LastProcessedBuyCloseTicket = latestClosedTicket;

   if(CountOrders(OP_BUYSTOP) > 0)
   {
      Print(EA_NAME,
            " BUY CLOSE DETECTED but BUY STOP already exists. ticket=",
            latestClosedTicket);
      return;
   }

   RefreshRates();
   double newBuyStop = NormalizePrice(Ask + PointsToPrice(MiniGrid1));
   double nextBuyLot = NextLot(latestClosedBuyLot);

   Print(EA_NAME,
         " BUY REENTRY TRIGGERED. closedTicket=", latestClosedTicket,
         " closedPrice=", DoubleToString(latestClosePrice, Digits),
         " previousLot=", DoubleToString(latestClosedBuyLot, DigitsLots),
         " nextLot=", DoubleToString(nextBuyLot, DigitsLots),
         " Ask=", DoubleToString(Ask, Digits),
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " newBUYSTOP=", DoubleToString(newBuyStop, Digits));

   SendPending(OP_BUYSTOP, newBuyStop, nextBuyLot, "EAGOLD BUY REENTRY MINIGRID1");
}

int OnInit()
{
   Print(EA_NAME, " v0.019 initialized. FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfitMoney=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " SELL trigger=", DoubleToString(2.0 * SmartGrid1, 0),
         " MiniGrid1=", DoubleToString(MiniGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots),
         " LotIncrement=", DoubleToString(LotIncrement, DigitsLots),
         " MaxOpenLot=", DoubleToString(MaxOpenLot, DigitsLots),
         " Multiplier=", DoubleToString(Multiplier, 2));

   InitializeBuyCloseTracker();
   CreateFirstStepOrders();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   TrailSellStop();
   TrailBuyStop();
   ProcessBuyTakeProfit();
   ProcessSellTakeProfit();
   ProcessSellProgression();
   ProcessBuyReentryAfterClose();
}
