'use strict'

const express = require('express')
const router = express.Router()

const PASSWORD = process.env.APP_PASSWORD || '13579'

router.get('/login', (req, res) => {
  if (req.session.authenticated) return res.redirect('/')
  res.render('login', { error: null })
})

router.post('/login', (req, res) => {
  if (req.body.password === PASSWORD) {
    req.session.authenticated = true
    return res.redirect('/')
  }
  res.render('login', { error: '비밀번호가 올바르지 않습니다.' })
})

router.post('/logout', (req, res) => {
  req.session.destroy()
  res.redirect('/login')
})

module.exports = router
