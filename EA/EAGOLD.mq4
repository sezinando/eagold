#property strict
#property version   "0.015"
#property description "EAGOLD - FirstStep, directional trailing, monetary TakeProfit and SELL progression"

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

// SELL STOP directional trailing applies to both the original FIRST STEP
// SELL STOP and SELL PROGRESSION pending orders.
// The rule is identical: while price rises, a SELL STOP may only move UP,
// never DOWN, and only after PendingStepTrail points of movement.
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
      {
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " Bid=", DoubleToString(bid, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " INITIAL BUY MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " close=", DoubleToString(bid, Digits));
      }
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
      {
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT close failed. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " Ask=", DoubleToString(ask, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME, " INITIAL SELL MONETARY TAKE PROFIT. ticket=", ticket,
               " profit=", DoubleToString(profit, 2),
               " targetMoney=", DoubleToString(TakeProfit, 2),
               " close=", DoubleToString(ask, Digits));
      }
   }
}

bool GetLatestSell(double &latestSellOpen, int &latestSellTicket)
{
   latestSellOpen   = 0.0;
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
         latestSellTicket = ticket;
      }
   }

   return(foundSell);
}

// SELL PROGRESSION:
// After the latest activated SELL, the price must move 2 x SmartGrid1
// AGAINST that SELL before a new SELL STOP is created.
// The new SELL STOP is placed at exactly latest SELL + SmartGrid1.
// Example with SmartGrid1=80:
// SELL at 5000 -> trigger at 5160 -> new SELL STOP at 5080.
void ProcessSellProgression()
{
   if(SmartGrid1 <= 0.0) return;

   // Never create another progression while a SELL STOP is already pending.
   if(CountOrders(OP_SELLSTOP) > 0)
      return;

   double latestSellOpen = 0.0;
   int latestSellTicket = -1;

   if(!GetLatestSell(latestSellOpen, latestSellTicket))
      return;

   RefreshRates();

   double triggerDistance = PointsToPrice(2.0 * SmartGrid1);
   double triggerPrice = NormalizePrice(latestSellOpen + triggerDistance);

   if(Bid < triggerPrice)
      return;

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
         " triggerDistance=", DoubleToString((Bid - latestSellOpen) / Point, 1),
         " newSELLSTOP=", DoubleToString(newSellStop, Digits));

   SendPending(OP_SELLSTOP, newSellStop, "EAGOLD SELL PROGRESSION");
}

int OnInit()
{
   Print(EA_NAME, " v0.015 initialized. FirstStep=", DoubleToString(FirstStep, 0),
         " PendingStepTrail=", DoubleToString(PendingStepTrail, 0),
         " TakeProfitMoney=", DoubleToString(TakeProfit, 2),
         " SmartGrid1=", DoubleToString(SmartGrid1, 0),
         " SELL trigger=", DoubleToString(2.0 * SmartGrid1, 0),
         " Lot=", DoubleToString(Lot, DigitsLots));

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
}
