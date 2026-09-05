#property strict
#property version   "0.005"
#property description "EAGOLD - FirstStep directional trailing and BUY TakeProfit"

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
input int    WaitSeconds               = 0;
input double FirstStep                 = 160.0;
input double MiniGrid1                = 250.0;
input double SmartGrid1               = 80.0;
input double MiniGrid2                = 80.0;
input double SmartGrid2               = 60.0;
input double PendingStepTrail         = 50.0;
input int    MaxTrades                = 2000;
input bool   EnableCloseBy            = false;
input double BuyProgressionTolerance  = 10.0;

string EA_NAME = "EAGOLD";

double PointsToPrice(double points)
{
   return(points * Point);
}

double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder())
         continue;

      if(OrderType() == type)
         count++;
   }

   return(count);
}

// Send one pending order at the requested price.
int SendPending(int type, double price, string comment)
{
   RefreshRates();

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   price = NormalizePrice(price);

   if(type == OP_BUYSTOP && price <= Ask + stopLevel)
      return(-1);

   if(type == OP_SELLSTOP && price >= Bid - stopLevel)
      return(-1);

   ResetLastError();

   int ticket = OrderSend(
      Symbol(),
      type,
      Lot,
      price,
      0,
      0,
      0,
      comment,
      MagicNumber,
      0,
      clrNONE
   );

   if(ticket < 0)
   {
      Print(EA_NAME,
            " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " error=", GetLastError());
   }
   else
   {
      Print(EA_NAME,
            " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(Lot, DigitsLots));
   }

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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(IsEAGOLDOrder())
         total++;
   }

   if(total > 0)
      return;

   RefreshRates();

   double buyPrice  = NormalizePrice(Ask + PointsToPrice(FirstStep));
   double sellPrice = NormalizePrice(Bid - PointsToPrice(FirstStep));

   Print(EA_NAME,
         " FIRST STEP. BID=", DoubleToString(Bid, Digits),
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
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder() || OrderType() != OP_BUYSTOP)
         continue;

      RefreshRates();

      double desired   = NormalizePrice(Ask + PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = current - desired;
      double trailStep = PointsToPrice(PendingStepTrail);

      // BUY STOP only moves downward.
      if(desired >= current)
         continue;

      // Modify only after the pending needs to move by PendingStepTrail.
      if(movement < trailStep)
         continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

      if(desired <= Ask + stopLevel)
         continue;

      ResetLastError();

      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
      {
         Print(EA_NAME,
               " BUY STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME,
               " BUY STOP TRAIL DOWN. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
      }
   }
}

// SELL STOP can only move UP.
// It follows a rising BID while preserving FirstStep distance.
// It NEVER moves back DOWN.
void TrailSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP)
         continue;

      RefreshRates();

      double desired   = NormalizePrice(Bid - PointsToPrice(FirstStep));
      double current   = OrderOpenPrice();
      double movement  = desired - current;
      double trailStep = PointsToPrice(PendingStepTrail);

      // SELL STOP only moves upward.
      if(desired <= current)
         continue;

      // Modify only after the pending needs to move by PendingStepTrail.
      if(movement < trailStep)
         continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

      if(desired >= Bid - stopLevel)
         continue;

      ResetLastError();

      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
      {
         Print(EAGOLD,
               " SELL STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME,
               " SELL STOP TRAIL UP. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits));
      }
   }
}

// BUY TAKE PROFIT:
// Close each open BUY when BID reaches the order open price + TakeProfit.
// TakeProfit is expressed in price points, just like FirstStep.
// No other BUY management is implemented here.
void ProcessBuyTakeProfit()
{
   if(TakeProfit <= 0.0)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder() || OrderType() != OP_BUY)
         continue;

      RefreshRates();

      double target = NormalizePrice(OrderOpenPrice() + PointsToPrice(TakeProfit));

      if(Bid < target)
         continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double closePrice = NormalizePrice(Bid);

      ResetLastError();

      if(!OrderClose(ticket, lots, closePrice, 0, clrNONE))
      {
         Print(EA_NAME,
               " BUY TAKE PROFIT close failed. ticket=", ticket,
               " open=", DoubleToString(OrderOpenPrice(), Digits),
               " target=", DoubleToString(target, Digits),
               " Bid=", DoubleToString(Bid, Digits),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME,
               " BUY TAKE PROFIT. ticket=", ticket,
               " open=", DoubleToString(OrderOpenPrice(), Digits),
               " target=", DoubleToString(target, Digits),
               " close=", DoubleToString(closePrice, Digits));
      }
   }
}

int OnInit()
{
   Print(EA_NAME,
         " v0.005 initialized. FirstStep=",
         DoubleToString(FirstStep, 0),
         " PendingStepTrail=",
         DoubleToString(PendingStepTrail, 0),
         " TakeProfit=",
         DoubleToString(TakeProfit, 2),
         " Lot=",
         DoubleToString(Lot, DigitsLots));

   CreateFirstStepOrders();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   // Current implemented behavior:
   // 1. Rising price  -> SELL STOP may move UP only.
   // 2. Falling price -> BUY STOP may move DOWN only.
   // 3. Open BUY     -> close at TakeProfit.
   // All other parameters remain intentionally inactive.
   TrailSellStop();
   TrailBuyStop();
   ProcessBuyTakeProfit();
}
