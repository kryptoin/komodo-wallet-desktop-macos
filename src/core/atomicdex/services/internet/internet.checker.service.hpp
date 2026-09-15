/******************************************************************************
 * Copyright © 2013-2024 The Komodo Platform Developers.                      *
 *                                                                            *
 * See the AUTHORS, DEVELOPER-AGREEMENT and LICENSE files at                  *
 * the top-level directory of this distribution for the individual copyright  *
 * holder information and the developer policies on copyright and licensing.  *
 *                                                                            *
 * Unless otherwise agreed in a custom licensing agreement, no part of the    *
 * Software is provided "AS IS", without warranty of any kind.                *
 *                                                                            *
 * Removal or modification of this copyright notice is prohibited.            *
 *                                                                            *
 ******************************************************************************/

#pragma once

//! QT
#include <QObject>

//! Deps
#include <antara/gaming/ecs/system.manager.hpp>

namespace atomic_dex
{
    //! Polls public endpoints to detect internet loss and drives the
    //! NoConnection interstitial (same QML contract as the 0.6.1 tree:
    //! `internet_reacheable`, `seconds_left_to_auto_retry`, `retry()`).
    //! Ported off cpprestsdk onto the in-house http.utilities client;
    //! liveness is decided by a public probe only (a localhost backend can
    //! never prove internet reachability). Optional market-data providers do
    //! not determine general internet reachability.
    class internet_service_checker final : public QObject, public ag::ecs::pre_update_system<internet_service_checker>
    {
        //! Q_Object definition
        Q_OBJECT

        Q_PROPERTY(bool internet_reacheable READ is_internet_alive NOTIFY internetStatusChanged)
        Q_PROPERTY(
            double seconds_left_to_auto_retry READ get_seconds_left_to_auto_retry WRITE set_seconds_left_to_auto_retry NOTIFY secondsLeftToAutoRetryChanged)
        //! Private typedefs
        using t_update_time_point = std::chrono::high_resolution_clock::time_point;

        //! Private members
        t_update_time_point m_update_clock;
        double              m_timer{60.0};
        std::atomic_bool    is_internet_reacheable{true};
        std::atomic_uint    m_probe_generation{0};
        std::atomic_bool    m_probe_succeeded{false};

        //! Private functions
        void fetch_internet_connection();
        void treat_probe_result(bool ok, const std::string& endpoint, unsigned int generation);

      signals:
        void internetStatusChanged();
        void secondsLeftToAutoRetryChanged();

      public:
        //! Constructor
        explicit internet_service_checker(entt::registry& registry, QObject* parent = nullptr);
        ~internet_service_checker() final = default;

        //! Public override
        void update() final;

        //! QT Properties
        [[nodiscard]] bool   is_internet_alive() const;
        [[nodiscard]] double get_seconds_left_to_auto_retry() const;
        void                 set_seconds_left_to_auto_retry(double time_left);

        void set_internet_alive(bool internet_status);

        Q_INVOKABLE void retry();
    };
} // namespace atomic_dex

REFL_AUTO(type(atomic_dex::internet_service_checker))
