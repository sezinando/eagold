#property strict
#property version   "0.002"
#property description "EAGOLD - FirstStep with pending trailing"

input int    MagicNumber       = 1001;
input double Lot               = 0.01;
input double FirstStep         = 160.0;
input double PendingStepTrail  = 50.0;

string EA_NAME = "EAGOLD";

// Convert a distance expressed in points to price.
double PointsToPrice(double points)
{
   return(points * Point);
}

// Normalize a price according to the symbol digits.
double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

// Check whether an order belongs to this EA and symbol.
bool IsEAGOLDOrder()
{
   return(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber);
}

// Count EAGOLD orders of a specific type.
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
   {
      Print(EA_NAME, " BUY STOP rejected: price too close to ASK. price=",
            DoubleToString(price, Digits),
            " Ask=", DoubleToString(Ask, Digits),
            " FirstStep=", DoubleToString(FirstStep, 0));
      return(-1);
   }

   if(type == OP_SELLSTOP && price >= Bid - stopLevel)
   {
      Print(EA_NAME, " SELL STOP rejected: price too close to BID. price=",
            DoubleToString(price, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " FirstStep=", DoubleToString(FirstStep, 0));
      return(-1);
   }

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
      int error = GetLastError();

      Print(EA_NAME,
            " OrderSend failed. type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(Lot, 2),
            " FirstStep=", DoubleToString(FirstStep, 0),
            " error=", error);
   }
   else
   {
      Print(EA_NAME,
            " pending created. ticket=", ticket,
            " type=", type,
            " price=", DoubleToString(price, Digits),
            " lot=", DoubleToString(Lot, 2),
            " FirstStep=", DoubleToString(FirstStep, 0));
   }

   return(ticket);
}

// FIRST STEP:
// Create exactly two pending orders around the current market price.
// BUY STOP  = ASK + FirstStep
// SELL STOP = BID - FirstStep
void CreateFirstStepOrders()
{
   // Do not create another initial pair if an EAGOLD order already exists.
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

// Move a BUY STOP whenever the desired FirstStep distance differs from
// the current pending price by at least PendingStepTrail.
void TrailBuyStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder() || OrderType() != OP_BUYSTOP)
         continue;

      RefreshRates();

      double desired = NormalizePrice(Ask + PointsToPrice(FirstStep));
      double current = OrderOpenPrice();
      double movement = MathAbs(desired - current);
      double trailStep = PointsToPrice(PendingStepTrail);

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
               " movement=", DoubleToString(movement / Point, 0),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME,
               " BUY STOP TRAIL. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits),
               " movement=", DoubleToString(movement / Point, 0),
               " FirstStep=", DoubleToString(FirstStep, 0),
               " PendingStepTrail=", DoubleToString(PendingStepTrail, 0));
      }
   }
}

// Move a SELL STOP whenever the desired FirstStep distance differs from
// the current pending price by at least PendingStepTrail.
void TrailSellStop()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(!IsEAGOLDOrder() || OrderType() != OP_SELLSTOP)
         continue;

      RefreshRates();

      double desired = NormalizePrice(Bid - PointsToPrice(FirstStep));
      double current = OrderOpenPrice();
      double movement = MathAbs(desired - current);
      double trailStep = PointsToPrice(PendingStepTrail);

      if(movement < trailStep)
         continue;

      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

      if(desired >= Bid - stopLevel)
         continue;

      ResetLastError();

      if(!OrderModify(OrderTicket(), desired, 0, 0, 0, clrNONE))
      {
         Print(EA_NAME,
               " SELL STOP modify failed. ticket=", OrderTicket(),
               " current=", DoubleToString(current, Digits),
               " desired=", DoubleToString(desired, Digits),
               " movement=", DoubleToString(movement / Point, 0),
               " error=", GetLastError());
      }
      else
      {
         Print(EA_NAME,
               " SELL STOP TRAIL. ticket=", OrderTicket(),
               " from=", DoubleToString(current, Digits),
               " to=", DoubleToString(desired, Digits),
               " movement=", DoubleToString(movement / Point, 0),
               " FirstStep=", DoubleToString(FirstStep, 0),
               " PendingStepTrail=", DoubleToString(PendingStepTrail, 0));
      }
   }
}

int OnInit()
{
   Print(EA_NAME,
         " v0.002 initialized. FirstStep=",
         DoubleToString(FirstStep, 0),
         " PendingStepTrail=",
         DoubleToString(PendingStepTrail, 0),
         " Lot=",
         DoubleToString(Lot, 2));

   CreateFirstStepOrders();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   TrailBuyStop();
   TrailSellStop();
}
