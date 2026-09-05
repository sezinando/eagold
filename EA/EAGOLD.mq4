//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.301"
#property description "EAGOLD - Two-order engine with robust FirstStep replacement."

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
// CONTADORES
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

//+------------------------------------------------------------------+

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

//+------------------------------------------------------------------+

double StepPrice()
{
   return(FirstStep * Point);
}

//+------------------------------------------------------------------+

double OrderProfitPoints()
{
   if(OrderType() == OP_BUY)
      return((Bid - OrderOpenPrice()) / Point);

   if(OrderType() == OP_SELL)
      return((OrderOpenPrice() - Ask) / Point);

   return(0);
}

//====================================================================
// CICLO INICIAL
//====================================================================

void StartCycle()
{
   RefreshRates();

   double buyPrice = NormalizeDouble(Ask, Digits);

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

   double sellPrice = NormalizeDouble(
      buyPrice - StepPrice(), Digits
   );

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if((buyPrice - sellPrice) < minimumDistance)
   {
      sellPrice = NormalizeDouble(
         buyPrice - minimumDistance, Digits
      );
   }

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

         if(!OrderClose(
            buyTicket, OrderLots(), Bid, Slippage, clrNONE
         ))
         {
            Print(
               "EAGOLD ERROR - Could not close BUY. Error=",
               GetLastError()
            );
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
// REPOSIÇÃO DA ORDEM FECHADA
//====================================================================
//
// A nova ordem continua sendo calculada a partir do preço da posição
// que permaneceu aberta. Porém, o tipo da pendente é escolhido de
// acordo com a posição do mercado:
//
// RESTOU BUY:
//   nível = BUY open - FirstStep
//   abaixo do mercado -> SELL STOP
//   acima do mercado  -> SELL LIMIT
//
// RESTOU SELL:
//   nível = SELL open + FirstStep
//   acima do mercado -> BUY STOP
//   abaixo do mercado -> BUY LIMIT
//
// Assim o EA não perde a segunda ordem simplesmente porque o mercado
// já ultrapassou o nível calculado durante o fechamento por gain.
//====================================================================

void PlaceReplacementOrder()
{
   if(CountOpenOrders() != 1)
      return;

   if(CountPendingOrders() != 0)
      return;

   RefreshRates();

   int remainingType   = -1;
   int remainingTicket = -1;
   double remainingPrice = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != MagicNumber) continue;

      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      remainingType    = OrderType();
      remainingTicket  = OrderTicket();
      remainingPrice   = OrderOpenPrice();
      break;
   }

   if(remainingTicket < 0)
      return;

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   //=================================================================
   // RESTOU BUY -> ORDEM OPOSTA NO NÍVEL BUY - FirstStep
   //=================================================================

   if(remainingType == OP_BUY)
   {
      double targetPrice = NormalizeDouble(
         remainingPrice - StepPrice(), Digits
      );

      int orderType = -1;

      // Nível abaixo do mercado: SELL STOP.
      if(targetPrice <= Bid - minimumDistance)
      {
         orderType = OP_SELLSTOP;
      }
      // Nível acima do mercado: SELL LIMIT.
      else if(targetPrice >= Ask + minimumDistance)
      {
         orderType = OP_SELLLIMIT;
      }
      else
      {
         Print(
            "EAGOLD - Replacement SELL level is inside broker stop distance. ",
            "Target=", DoubleToString(targetPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits),
            " StopLevel=", DoubleToString(minimumDistance / Point, 0),
            " points"
         );
         return;
      }

      ResetLastError();

      int ticket = OrderSend(
         Symbol(), orderType, Lots, targetPrice, Slippage,
         0, 0, "EAGOLD REPLACEMENT SELL", MagicNumber, 0, clrNONE
      );

      if(ticket < 0)
      {
         int error = GetLastError();
         Print(
            "EAGOLD ERROR - Replacement SELL failed. Error=", error,
            " Type=", orderType,
            " Target=", DoubleToString(targetPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits)
         );
         return;
      }

      Print(
         "EAGOLD - Replacement SELL placed.",
         " Ticket=", ticket,
         " Type=", orderType == OP_SELLSTOP ? "SELL STOP" : "SELL LIMIT",
         " Price=", DoubleToString(targetPrice, Digits),
         " Reference BUY=", DoubleToString(remainingPrice, Digits),
         " FirstStep=", FirstStep, " points"
      );

      return;
   }

   //=================================================================
   // RESTOU SELL -> ORDEM OPOSTA NO NÍVEL SELL + FirstStep
   //=================================================================

   if(remainingType == OP_SELL)
   {
      double targetPrice = NormalizeDouble(
         remainingPrice + StepPrice(), Digits
      );

      int orderType = -1;

      // Nível acima do mercado: BUY STOP.
      if(targetPrice >= Ask + minimumDistance)
      {
         orderType = OP_BUYSTOP;
      }
      // Nível abaixo do mercado: BUY LIMIT.
      else if(targetPrice <= Bid - minimumDistance)
      {
         orderType = OP_BUYLIMIT;
      }
      else
      {
         Print(
            "EAGOLD - Replacement BUY level is inside broker stop distance. ",
            "Target=", DoubleToString(targetPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits),
            " StopLevel=", DoubleToString(minimumDistance / Point, 0),
            " points"
         );
         return;
      }

      ResetLastError();

      int ticket = OrderSend(
         Symbol(), orderType, Lots, targetPrice, Slippage,
         0, 0, "EAGOLD REPLACEMENT BUY", MagicNumber, 0, clrNONE
      );

      if(ticket < 0)
      {
         int error = GetLastError();
         Print(
            "EAGOLD ERROR - Replacement BUY failed. Error=", error,
            " Type=", orderType,
            " Target=", DoubleToString(targetPrice, Digits),
            " Bid=", DoubleToString(Bid, Digits),
            " Ask=", DoubleToString(Ask, Digits)
         );
         return;
      }

      Print(
         "EAGOLD - Replacement BUY placed.",
         " Ticket=", ticket,
         " Type=", orderType == OP_BUYSTOP ? "BUY STOP" : "BUY LIMIT",
         " Price=", DoubleToString(targetPrice, Digits),
         " Reference SELL=", DoubleToString(remainingPrice, Digits),
         " FirstStep=", FirstStep, " points"
      );

      return;
   }
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

      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      double profitPoints = OrderProfitPoints();

      if(profitPoints >= ProfitTarget)
      {
         int ticket = OrderTicket();
         double lots = OrderLots();

         double closePrice;

         if(OrderType() == OP_BUY)
            closePrice = Bid;
         else
            closePrice = Ask;

         ResetLastError();

         bool closed = OrderClose(
            ticket,
            lots,
            closePrice,
            Slippage,
            clrNONE
         );

         if(closed)
         {
            Print(
               "EAGOLD - Order closed by ProfitTarget.",
               " Ticket=", ticket,
               " ProfitPoints=", DoubleToString(profitPoints, 1)
            );
         }
         else
         {
            Print(
               "EAGOLD ERROR - OrderClose failed.",
               " Ticket=", ticket,
               " Error=", GetLastError()
            );
         }
      }
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==================================================");
   Print("EAGOLD v0.3.1 INITIALIZED");
   Print("Two-order replacement engine");
   Print("FirstStep    = ", FirstStep, " points");
   Print("ProfitTarget = ", ProfitTarget, " points");
   Print("MagicNumber  = ", MagicNumber);
   Print("Lots         = ", DoubleToString(Lots, 2));
   Print("==================================================");

   CycleStarted = false;

   return(INIT_SUCCEEDED);
}

//====================================================================
// DEINIT
//====================================================================

void OnDeinit(const int reason)
{
   Print(
      "EAGOLD v0.3.1 DEINITIALIZED. Reason=",
      reason
   );
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   ManageOrders();

   int openOrders    = CountOpenOrders();
   int pendingOrders = CountPendingOrders();

   // Nenhuma posição e nenhuma pendente: inicia novo ciclo.
   if(openOrders == 0 && pendingOrders == 0)
   {
      if(CycleStarted)
      {
         Print("EAGOLD - Cycle finished.");
         CycleStarted = false;
      }

      StartCycle();
      return;
   }

   // Uma posição aberta e nenhuma pendente: uma ordem foi fechada
   // pelo ProfitTarget. Recria a ordem oposta no nível FirstStep.
   if(openOrders == 1 && pendingOrders == 0)
   {
      PlaceReplacementOrder();
      return;
   }
}

//+------------------------------------------------------------------+
