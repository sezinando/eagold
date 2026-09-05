//+------------------------------------------------------------------+
//|                                                   EAGOLD.mq4     |
//|                         EAGOLD - Expert Advisor for MT4          |
//+------------------------------------------------------------------+
#property strict
#property version   "000.401"
#property description "EAGOLD - Independent operations with successor after close."

input int    MagicNumber  = 1001;
input double Lots         = 0.01;
input int    FirstStep    = 150;
input int    ProfitTarget = 150;
input int    Slippage     = 10;

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
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
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
         count++;
   }
   return(count);
}

//====================================================================
// CÁLCULOS
//====================================================================

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
// ABRE UMA OPERAÇÃO INDEPENDENTE
//====================================================================
//
// A operação é formada por:
//   1. uma posição a mercado;
//   2. sua ordem oposta pendente a FirstStep.
//
// A pendente pertence a esta operação e não impede que outra operação
// independente seja criada posteriormente após o fechamento da posição.
//====================================================================

bool StartIndependentOperation(int direction)
{
   RefreshRates();

   int marketType;
   int pendingType;
   double marketPrice;
   double pendingPrice;

   if(direction == OP_BUY)
   {
      marketType   = OP_BUY;
      pendingType  = OP_SELLSTOP;
      marketPrice  = NormalizeDouble(Ask, Digits);
      pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
   }
   else if(direction == OP_SELL)
   {
      marketType   = OP_SELL;
      pendingType  = OP_BUYSTOP;
      marketPrice  = NormalizeDouble(Bid, Digits);
      pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }
   else
   {
      return(false);
   }

   int marketTicket = OrderSend(
      Symbol(), marketType, Lots, marketPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD BUY" : "EAGOLD SELL",
      MagicNumber, 0, clrNONE
   );

   if(marketTicket < 0)
   {
      Print("EAGOLD ERROR - Market order failed. Direction=",
            direction == OP_BUY ? "BUY" : "SELL",
            " Error=", GetLastError());
      return(false);
   }

   // Usa o preço real de execução como referência do FirstStep.
   if(OrderSelect(marketTicket, SELECT_BY_TICKET))
   {
      marketPrice = OrderOpenPrice();

      if(direction == OP_BUY)
         pendingPrice = NormalizeDouble(marketPrice - StepPrice(), Digits);
      else
         pendingPrice = NormalizeDouble(marketPrice + StepPrice(), Digits);
   }

   RefreshRates();

   double minimumDistance = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(direction == OP_BUY)
   {
      if((Bid - pendingPrice) < minimumDistance)
      {
         Print("EAGOLD ERROR - SELL STOP too close to market. Ticket=",
               marketTicket, " StopLevel condition.");
         return(true);
      }
   }
   else
   {
      if((pendingPrice - Ask) < minimumDistance)
      {
         Print("EAGOLD ERROR - BUY STOP too close to market. Ticket=",
               marketTicket, " StopLevel condition.");
         return(true);
      }
   }

   ResetLastError();

   int pendingTicket = OrderSend(
      Symbol(), pendingType, Lots, pendingPrice, Slippage,
      0, 0,
      direction == OP_BUY ? "EAGOLD SELL" : "EAGOLD BUY",
      MagicNumber, 0, clrNONE
   );

   if(pendingTicket < 0)
   {
      Print("EAGOLD ERROR - Opposite pending order failed. MarketTicket=",
            marketTicket,
            " Type=", pendingType,
            " Price=", DoubleToString(pendingPrice, Digits),
            " Error=", GetLastError());
      return(true);
   }

   Print("EAGOLD - Independent operation started. Direction=",
         direction == OP_BUY ? "BUY" : "SELL",
         " MarketTicket=", marketTicket,
         " MarketPrice=", DoubleToString(marketPrice, Digits),
         " PendingTicket=", pendingTicket,
         " PendingPrice=", DoubleToString(pendingPrice, Digits),
         " FirstStep=", FirstStep, " points");

   return(true);
}

//====================================================================
// GERENCIAMENTO DAS ORDENS
//====================================================================
//
// REGRA FUNDAMENTAL:
//
//   posição aberta NÃO gera nova posição enquanto permanecer aberta.
//
//   posição fechada por ProfitTarget -> gera UMA nova posição na
//   mesma direção.
//
// A existência de uma ordem oposta pendente NÃO altera esta regra.
// Portanto:
//
//   BUY aberta + SELL STOP pendente
//       -> enquanto BUY não fechar: NÃO abre outra BUY.
//
//   BUY fecha no gain
//       -> abre NOVA BUY.
//       -> SELL STOP anterior permanece.
//       -> nova BUY recebe sua própria SELL STOP.
//
// As operações são independentes.
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

      int direction = OrderType();
      double profitPoints = OrderProfitPoints();

      // Enquanto a posição não atingir o gain, NÃO cria outra posição.
      if(profitPoints < ProfitTarget)
         continue;

      int ticket = OrderTicket();
      double lots = OrderLots();
      double closePrice = direction == OP_BUY ? Bid : Ask;

      ResetLastError();

      bool closed = OrderClose(
         ticket, lots, closePrice, Slippage, clrNONE
      );

      if(!closed)
      {
         Print("EAGOLD ERROR - OrderClose failed. Ticket=",
               ticket, " Error=", GetLastError());
         continue;
      }

      Print("EAGOLD - Order closed by ProfitTarget. Ticket=", ticket,
            " Direction=", direction == OP_BUY ? "BUY" : "SELL",
            " ProfitPoints=", DoubleToString(profitPoints, 1));

      // SOMENTE AGORA nasce a sucessora desta operação.
      // Nenhuma posição nova é criada antes deste fechamento.
      StartIndependentOperation(direction);
   }
}

//====================================================================
// INIT
//====================================================================

int OnInit()
{
   Print("==================================================");
   Print("EAGOLD v0.4.1 INITIALIZED");
   Print("Independent operations / successor only after close");
   Print("FirstStep    = ", FirstStep, " points");
   Print("ProfitTarget = ", ProfitTarget, " points");
   Print("MagicNumber  = ", MagicNumber);
   Print("Lots         = ", DoubleToString(Lots, 2));
   Print("==================================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   Print("EAGOLD v0.4.1 DEINITIALIZED. Reason=", reason);
}

//====================================================================
// TICK
//====================================================================

void OnTick()
{
   ManageOrders();

   // Primeira operação somente se não existir nenhuma operação ou
   // pendente do EAGOLD. A presença de uma pendente, por si só,
   // nunca dispara uma nova posição.
   if(CountOpenOrders() == 0 && CountPendingOrders() == 0)
      StartIndependentOperation(OP_BUY);
}

//+------------------------------------------------------------------+
