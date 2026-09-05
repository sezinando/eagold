//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "0.2.0"
#property description "EAGOLD - Initial two-order distance engine."

//====================================================================
// INPUTS
//====================================================================

input int    MagicNumber  = 1001;
input double Lots         = 0.01;
input int    FirstStep    = 150;
input int    ProfitTarget = 150;
input int    Slippage     = 10;

//====================================================================
// VARIÁVEIS
//====================================================================

bool CycleStarted = false;

//====================================================================
// FUNÇÕES AUXILIARES
//====================================================================

int CountOpenOrders()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         count++;
   }

   return(count);
}

int CountPendingOrders()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      int type = OrderType();

      if(type == OP_BUYLIMIT || type == OP_BUYSTOP ||
         type == OP_SELLLIMIT || type == OP_SELLSTOP)
      {
         count++;
      }
   }

   return(count);
}

int CountEAGOLDOrders()
{
   return(CountOpenOrders() + CountPendingOrders());
}

double StepPrice()
{
   return(FirstStep * Point);
}

double OrderProfitPoints()
{
   if(OrderType() == OP_BUY)
      return((Bid - OrderOpenPrice()) / Point);

   if(OrderType() == OP_SELL)
      return((OrderOpenPrice() - Ask) / Point);

   return(0);
}

//====================================================================
// ABERTURA DO CICLO
//====================================================================

void StartCycle()
{
   RefreshRates();

   double buyPrice = Ask;

   // BUY A MERCADO
   int buyTicket = OrderSend(
      Symbol(), OP_BUY, Lots, buyPrice, Slippage,
      0, 0, "EAGOLD BUY", MagicNumber, 0, clrNONE
   );

   if(buyTicket < 0)
   {
      Print("EAGOLD ERROR - BUY failed. Error=", GetLastError());
      return;
   }

   Print("EAGOLD - BUY opened. Ticket=", buyTicket,
         " Price=", DoubleToString(buyPrice, Digits));

   // SELL STOP A FirstStep PONTOS
   double sellPrice = NormalizeDouble(buyPrice - StepPrice(), Digits);

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if((buyPrice - sellPrice) < minimumDistance)
      sellPrice = NormalizeDouble(buyPrice - minimumDistance, Digits);

   int sellTicket = OrderSend(
      Symbol(), OP_SELLSTOP, Lots, sellPrice, Slippage,
      0, 0, "EAGOLD SELL", MagicNumber, 0, clrNONE
   );

   if(sellTicket < 0)
   {
      Print("EAGOLD ERROR - SELL STOP failed. Error=", GetLastError());

      if(OrderSelect(buyTicket, SELECT_BY_TICKET))
      {
         RefreshRates();

         if(!OrderClose(buyTicket, OrderLots(), Bid, Slippage, clrNONE))
         {
            Print("EAGOLD ERROR - Could not close BUY after SELL STOP failure. Error=",
                  GetLastError());
         }
      }

      return;
   }

   Print("EAGOLD - SELL STOP placed. Ticket=", sellTicket,
         " Price=", DoubleToString(sellPrice, Digits),
         " Distance=", FirstStep, " points");

   CycleStarted = true;
}

//====================================================================
// GERENCIAMENTO DAS ORDENS
//====================================================================

void ManageOrders()
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double profitPoints = OrderProfitPoints();

      if(profitPoints >= ProfitTarget)
      {
         int ticket = OrderTicket();
         double lots = OrderLots();
         double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;

         bool closed = OrderClose(
            ticket, lots, closePrice, Slippage, clrNONE
         );

         if(closed)
         {
            Print("EAGOLD - Order closed by ProfitTarget. Ticket=", ticket,
                  " ProfitPoints=", DoubleToString(profitPoints, 1));
         }
         else
         {
            Print("EAGOLD ERROR - OrderClose failed. Ticket=", ticket,
                  " Error=", GetLastError());
         }
      }
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==============================================");
   Print("EAGOLD v0.2.0 INITIALIZED");
   Print("FirstStep     = ", FirstStep, " points");
   Print("ProfitTarget  = ", ProfitTarget, " points");
   Print("MagicNumber   = ", MagicNumber);
   Print("Lots          = ", DoubleToString(Lots, 2));
   Print("==============================================");

   CycleStarted = false;

   return(INIT_SUCCEEDED);
}

//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   Print("EAGOLD v0.2.0 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   ManageOrders();

   int totalOrders = CountEAGOLDOrders();

   if(totalOrders == 0)
   {
      if(CycleStarted)
      {
         Print("EAGOLD - Cycle finished.");
         CycleStarted = false;
      }

      StartCycle();
      return;
   }

   if(CountOpenOrders() == 0 && CountPendingOrders() > 0)
      return;
}

//+------------------------------------------------------------------+
