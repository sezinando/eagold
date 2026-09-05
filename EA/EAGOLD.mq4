//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.300"
#property description "EAGOLD - Two-order engine with FirstStep replacement."

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

int CountEAGOLDOrders()
{
   return(CountOpenOrders() + CountPendingOrders());
}

//====================================================================
// CÁLCULOS
//====================================================================

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

   //=================================================================
   // BUY A MERCADO
   //=================================================================

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

   //=================================================================
   // SELL STOP A FirstStep ABAIXO DA BUY
   //=================================================================

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
// Se restar BUY:
//     nova SELL STOP = preço de abertura da BUY - FirstStep
//
// Se restar SELL:
//     nova BUY STOP = preço de abertura da SELL + FirstStep
//
// A distância é calculada a partir da posição que permaneceu aberta,
// e não do preço corrente. Assim o FirstStep é preservado.
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

   //=================================================================
   // LOCALIZA A ÚNICA POSIÇÃO ABERTA
   //=================================================================

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
   // RESTOU BUY -> SELL STOP FirstStep ABAIXO DA BUY
   //=================================================================

   if(remainingType == OP_BUY)
   {
      double sellPrice = NormalizeDouble(
         remainingPrice - StepPrice(), Digits
      );

      if((Bid - sellPrice) < minimumDistance)
      {
         Print(
            "EAGOLD ERROR - Replacement SELL STOP is too close to market. ",
            "Required FirstStep=", FirstStep,
            " points."
         );
         return;
      }

      int ticket = OrderSend(
         Symbol(), OP_SELLSTOP, Lots, sellPrice, Slippage,
         0, 0, "EAGOLD REPLACEMENT SELL", MagicNumber, 0, clrNONE
      );

      if(ticket < 0)
      {
         Print(
            "EAGOLD ERROR - Replacement SELL STOP failed. Error=",
            GetLastError()
         );
         return;
      }

      Print(
         "EAGOLD - Replacement SELL STOP placed.",
         " Ticket=", ticket,
         " Price=", DoubleToString(sellPrice, Digits),
         " Reference BUY=", DoubleToString(remainingPrice, Digits),
         " FirstStep=", FirstStep, " points"
      );

      return;
   }

   //=================================================================
   // RESTOU SELL -> BUY STOP FirstStep ACIMA DA SELL
   //=================================================================

   if(remainingType == OP_SELL)
   {
      double buyPrice = NormalizeDouble(
         remainingPrice + StepPrice(), Digits
      );

      if((buyPrice - Ask) < minimumDistance)
      {
         Print(
            "EAGOLD ERROR - Replacement BUY STOP is too close to market. ",
            "Required FirstStep=", FirstStep,
            " points."
         );
         return;
      }

      int ticket = OrderSend(
         Symbol(), OP_BUYSTOP, Lots, buyPrice, Slippage,
         0, 0, "EAGOLD REPLACEMENT BUY", MagicNumber, 0, clrNONE
      );

      if(ticket < 0)
      {
         Print(
            "EAGOLD ERROR - Replacement BUY STOP failed. Error=",
            GetLastError()
         );
         return;
      }

      Print(
         "EAGOLD - Replacement BUY STOP placed.",
         " Ticket=", ticket,
         " Price=", DoubleToString(buyPrice, Digits),
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
   Print("EAGOLD v0.3.0 INITIALIZED");
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
      "EAGOLD v0.3.0 DEINITIALIZED. Reason=",
      reason
   );
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   //=================================================================
   // 1. GERENCIA AS POSIÇÕES
   //=================================================================

   ManageOrders();

   int openOrders    = CountOpenOrders();
   int pendingOrders = CountPendingOrders();

   //=================================================================
   // 2. NENHUMA POSIÇÃO E NENHUMA PENDENTE
   //
   // Inicia um novo ciclo.
   //=================================================================

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

   //=================================================================
   // 3. UMA POSIÇÃO ABERTA E NENHUMA PENDENTE
   //
   // Uma das posições foi fechada por ProfitTarget.
   // Cria a posição oposta respeitando FirstStep em relação à
   // posição que permaneceu aberta.
   //=================================================================

   if(openOrders == 1 && pendingOrders == 0)
   {
      PlaceReplacementOrder();
      return;
   }

   //=================================================================
   // 4. DOIS ORDENS ABERTAS OU UMA PENDENTE
   //
   // Mantém o estado atual.
   //=================================================================
}

//+------------------------------------------------------------------+
